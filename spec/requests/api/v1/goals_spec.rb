require "rails_helper"

RSpec.describe "Api::V1::Goals", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "GET /api/v1/goals" do
    it "returns JSON 401 without a token" do
      get api_v1_goals_path

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("unauthorized")
    end

    it "groups goals by status and hides other users' goals" do
      create(:goal, user: user, name: "Active goal")
      create(:goal, user: user, name: "Done goal", status: "achieved", current_value: 100)
      create(:goal, user: user, name: "Dropped goal", status: "abandoned")
      create(:goal, name: "Someone else's")

      get api_v1_goals_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["active"].map { |g| g["name"] }).to eq([ "Active goal" ])
      expect(body["achieved"].map { |g| g["name"] }).to eq([ "Done goal" ])
      expect(body["abandoned"].map { |g| g["name"] }).to eq([ "Dropped goal" ])
    end

    it "recalculates active goals before rendering" do
      account = create(:account, user: user, initial_balance_cents: 250_00)
      create(:goal, user: user, name: "Save up", target_type: "financial", related: account,
                    target_value: 1000, current_value: 0)

      get api_v1_goals_path, headers: auth

      goal_json = JSON.parse(response.body)["active"].first
      expect(goal_json["current_value"]).to eq(250.0)
      expect(goal_json["progress_percent"]).to eq(25.0)
    end

    it "moves an active goal that reaches its target into the achieved group" do
      account = create(:account, user: user, initial_balance_cents: 500_00)
      create(:goal, user: user, name: "Small target", target_type: "financial", related: account,
                    target_value: 100, current_value: 0)

      get api_v1_goals_path, headers: auth

      body = JSON.parse(response.body)
      expect(body["active"]).to be_empty
      expect(body["achieved"].map { |g| g["name"] }).to eq([ "Small target" ])
    end

    it "serializes the full goal shape with deadline badge" do
      account = create(:account, user: user, name: "Vault", currency: "TRY", initial_balance_cents: 40_000)
      create(:goal, user: user, name: "Emergency fund", description: "3 months", target_type: "financial",
                    related: account, target_value: 1000, current_value: 0, unit: "TRY",
                    deadline: Date.current + 5, color: "#B8860B")

      get api_v1_goals_path, headers: auth

      expect(JSON.parse(response.body)["active"].first).to include(
        "name" => "Emergency fund", "description" => "3 months", "target_type" => "financial",
        "status" => "active", "color" => "#B8860B", "unit" => "TRY",
        "deadline" => (Date.current + 5).iso8601, "days_remaining" => 5,
        "target_value" => 1000.0, "current_value" => 400.0, "progress_percent" => 40.0,
        "deadline_badge" => { "state" => "soon", "days" => 5 }
      )
    end

    it "serializes a related account with balance and subunit" do
      account = create(:account, user: user, name: "Vault", currency: "TRY", initial_balance_cents: 40_000)
      create(:goal, user: user, target_type: "financial", related: account, target_value: 1000)

      get api_v1_goals_path, headers: auth

      expect(JSON.parse(response.body)["active"].first["related"]).to eq(
        "type" => "Account", "id" => account.id, "name" => "Vault",
        "balance_cents" => 40_000, "currency" => "TRY", "subunit_to_unit" => 100
      )
    end

    it "renders every deadline_badge state" do
      create(:goal, user: user, name: "Overdue", deadline: Date.current - 3)
      create(:goal, user: user, name: "Today", deadline: Date.current)
      create(:goal, user: user, name: "Soon", deadline: Date.current + 5)
      create(:goal, user: user, name: "Far", deadline: Date.current + 30)
      create(:goal, user: user, name: "No deadline")

      get api_v1_goals_path, headers: auth

      badges = JSON.parse(response.body)["active"].to_h { |g| [ g["name"], g["deadline_badge"] ] }
      expect(badges["Overdue"]).to eq("state" => "overdue", "days" => 3)
      expect(badges["Today"]).to eq("state" => "today", "days" => 0)
      expect(badges["Soon"]).to eq("state" => "soon", "days" => 5)
      expect(badges["Far"]).to eq("state" => "far", "days" => 30)
      expect(badges["No deadline"]).to be_nil
    end
  end

  describe "GET /api/v1/goals/:id" do
    it "recalculates and returns the goal" do
      habit = create(:habit, user: user, name: "Run")
      create(:habit_log, habit: habit, date: Date.current, completed: true)
      create(:habit_log, habit: habit, date: Date.current - 1, completed: true)
      goal = create(:goal, user: user, target_type: "habit", related: habit,
                           target_value: 10, current_value: 0)

      get api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(2.0)
      expect(goal_json["related"]).to include(
        "type" => "Habit", "id" => habit.id, "name" => "Run", "current_streak" => 2, "completed_days" => 2
      )
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      get api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end
  end

  describe "POST /api/v1/goals" do
    it "creates a goal with a composite Account related param" do
      account = create(:account, user: user, name: "Gold", currency: "GAU", initial_balance_cents: 120)

      post api_v1_goals_path, headers: auth,
           params: { name: "Gold stash", target_type: "financial", target_value: 500,
                     unit: "gr", related: "Account-#{account.id}" }, as: :json

      expect(response).to have_http_status(:created)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json).to include("name" => "Gold stash", "target_type" => "financial", "unit" => "gr")
      expect(goal_json["related"]).to include(
        "type" => "Account", "id" => account.id, "balance_cents" => 120, "currency" => "GAU", "subunit_to_unit" => 1
      )
    end

    it "creates a goal with a composite Habit related param" do
      habit = create(:habit, user: user, name: "Meditate")

      post api_v1_goals_path, headers: auth,
           params: { name: "Meditation streak", target_type: "habit", target_value: 30,
                     unit: "days", related: "Habit-#{habit.id}" }, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["goal"]["related"]).to include("type" => "Habit", "id" => habit.id)
    end

    it "404s for a related param pointing at another user's account, creating nothing" do
      other_account = create(:account)

      post api_v1_goals_path, headers: auth,
           params: { name: "Sneaky", target_type: "financial", target_value: 100,
                     related: "Account-#{other_account.id}" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to eq("error" => "not_found", "code" => "not_found")
      expect(user.goals).to be_empty
    end

    it "returns 422 with field errors for an invalid goal" do
      post api_v1_goals_path, headers: auth, params: { name: "", target_value: 10 }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to have_key("name")
    end
  end

  describe "PATCH /api/v1/goals/:id" do
    it "updates attributes and clears related with \"none\"" do
      account = create(:account, user: user)
      goal = create(:goal, user: user, target_type: "financial", related: account)

      patch api_v1_goal_path(goal), headers: auth,
            params: { name: "Renamed", target_value: 750, related: "none" }, as: :json

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json).to include("name" => "Renamed", "target_value" => 750.0)
      expect(goal_json["related"]).to be_nil
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch api_v1_goal_path(goal), headers: auth, params: { name: "Hijack" }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/goals/:id/update_progress" do
    it "applies a delta" do
      goal = create(:goal, user: user, target_value: 100, current_value: 40)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 5 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["goal"]["current_value"]).to eq(45.0)
    end

    it "sets an absolute current_value" do
      goal = create(:goal, user: user, target_value: 100, current_value: 40)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { current_value: 90 }, as: :json

      expect(JSON.parse(response.body)["goal"]["current_value"]).to eq(90.0)
    end

    it "clamps a negative result at 0" do
      goal = create(:goal, user: user, target_value: 100, current_value: 3)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: -10 }, as: :json

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(0.0)
      expect(goal_json["status"]).to eq("active")
    end

    it "auto-achieves when the target is reached" do
      goal = create(:goal, user: user, target_value: 100, current_value: 99)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 1 }, as: :json

      expect(JSON.parse(response.body)["goal"]["status"]).to eq("achieved")
    end

    it "keeps an abandoned goal abandoned" do
      goal = create(:goal, user: user, target_value: 100, current_value: 0, status: "abandoned")

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { current_value: 100 }, as: :json

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["status"]).to eq("abandoned")
      expect(goal_json["current_value"]).to eq(100.0)
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 1 }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/goals/:id/recalculate" do
    it "computes GAU progress with subunit_to_unit 1 (grams, not /100)" do
      account = create(:account, user: user, currency: "GAU", initial_balance_cents: 412)
      goal = create(:goal, user: user, target_type: "financial", related: account,
                           target_value: 500, current_value: 0, unit: "gr")

      patch recalculate_api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:ok)
      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(412.0)
      expect(goal_json["progress_percent"]).to eq(82.4)
      expect(goal_json["related"]).to include("balance_cents" => 412, "subunit_to_unit" => 1)
    end

    it "computes TRY progress with subunit_to_unit 100" do
      account = create(:account, user: user, currency: "TRY", initial_balance_cents: 41_200)
      goal = create(:goal, user: user, target_type: "financial", related: account,
                           target_value: 500, current_value: 0)

      patch recalculate_api_v1_goal_path(goal), headers: auth

      goal_json = JSON.parse(response.body)["goal"]
      expect(goal_json["current_value"]).to eq(412.0)
      expect(goal_json["progress_percent"]).to eq(82.4)
    end

    it "404s for another user's goal" do
      goal = create(:goal)

      patch recalculate_api_v1_goal_path(goal), headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  # G4: delete, status rules, linking after creation, strict parameters.
  describe "G4 changes" do
    def body = JSON.parse(response.body)

    def patch_goal(goal, params)
      patch api_v1_goal_path(goal), headers: auth, params: params, as: :json
      body
    end

    it "401s on the new and changed endpoints without a token" do
      goal = create(:goal, user: user)

      delete api_v1_goal_path(goal)
      expect(response).to have_http_status(:unauthorized)
      expect(body["code"]).to eq("unauthorized")

      patch api_v1_goal_path(goal), params: { status: "abandoned" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(goal.reload.status).to eq("active")
    end

    describe "progress_source" do
      it "says where each goal's value comes from" do
        account = create(:account, user: user)
        habit = create(:habit, user: user)
        create(:goal, user: user, name: "Hesap", target_type: "financial", related: account)
        create(:goal, user: user, name: "Gelir", target_type: "financial")
        create(:goal, user: user, name: "Alışkanlık", target_type: "habit", related: habit)
        create(:goal, user: user, name: "Bağsız alışkanlık", target_type: "habit")
        create(:goal, user: user, name: "Özel", target_type: "custom")

        get api_v1_goals_path, headers: auth

        sources = body["active"].to_h { |goal| [ goal["name"], goal["progress_source"] ] }
        expect(sources).to eq(
          "Hesap" => "account", "Gelir" => "income", "Alışkanlık" => "habit",
          "Bağsız alışkanlık" => "manual", "Özel" => "manual"
        )
      end
    end

    describe "GET /api/v1/goals" do
      it "recomputes achieved goals too, so the list and the detail agree" do
        account = create(:account, user: user, initial_balance_cents: 50_00)
        goal = create(:goal, user: user, name: "Düştü", target_type: "financial", related: account,
                             target_value: 100, current_value: 120, status: "achieved")

        get api_v1_goals_path, headers: auth

        expect(body["achieved"]).to be_empty
        expect(body["active"].map { |g| [ g["name"], g["current_value"] ] }).to eq([ [ "Düştü", 50.0 ] ])

        get api_v1_goal_path(goal), headers: auth
        expect(body["goal"]).to include("status" => "active", "current_value" => 50.0)
      end

      it "keeps abandoned goals abandoned while refreshing their value" do
        account = create(:account, user: user, initial_balance_cents: 500_00)
        create(:goal, user: user, target_type: "financial", related: account,
                      target_value: 100, current_value: 0, status: "abandoned")

        get api_v1_goals_path, headers: auth

        expect(body["abandoned"].sole).to include("status" => "abandoned", "current_value" => 500.0)
      end

      it "does not write a goal whose value and status are unchanged" do
        goal = create(:goal, user: user, target_value: 100, current_value: 10)
        goal.update_columns(updated_at: 2.days.ago)

        expect { get api_v1_goals_path, headers: auth }.not_to(change { goal.reload.attributes })
      end
    end

    describe "DELETE /api/v1/goals/:id" do
      it "deletes the goal and unlinks its habits, todos and subscriptions" do
        goal = create(:goal, user: user)
        habit = create(:habit, user: user, goal: goal)
        todo = create(:todo, user: user, goal: goal)
        subscription = create(:subscription, user: user, goal: goal)

        delete api_v1_goal_path(goal), headers: auth

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(Goal.exists?(goal.id)).to be(false)
        expect([ habit.reload.goal_id, todo.reload.goal_id, subscription.reload.goal_id ]).to all(be_nil)
      end

      it "404s for another user's goal and deletes nothing" do
        goal = create(:goal)

        delete api_v1_goal_path(goal), headers: auth

        expect(response).to have_http_status(:not_found)
        expect(body).to eq("error" => "not_found", "code" => "not_found")
        expect(Goal.exists?(goal.id)).to be(true)
      end

      it "404s for an id that does not exist" do
        delete api_v1_goal_path(id: 0), headers: auth

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "PATCH /api/v1/goals/:id status" do
      it "abandons an active goal, which then stays abandoned on every read" do
        goal = create(:goal, user: user, target_value: 100, current_value: 100, status: "achieved")

        expect(patch_goal(goal, { status: "abandoned" })["goal"]["status"]).to eq("abandoned")

        get api_v1_goal_path(goal), headers: auth
        expect(body["goal"]["status"]).to eq("abandoned")
        get api_v1_goals_path, headers: auth
        expect(body["abandoned"].map { |g| g["id"] }).to eq([ goal.id ])
      end

      it "reopens an abandoned goal that is below its target" do
        goal = create(:goal, user: user, target_value: 100, current_value: 30, status: "abandoned")

        expect(patch_goal(goal, { status: "active" })["goal"]).to include("status" => "active", "current_value" => 30.0)
        expect(goal.reload.status).to eq("active")
      end

      it "refuses to reopen a goal at its target, saving nothing" do
        account = create(:account, user: user, initial_balance_cents: 150_00)
        goal = create(:goal, user: user, name: "Eski", target_type: "financial", related: account,
                             target_value: 100, current_value: 0, status: "abandoned")

        json = patch_goal(goal, { status: "active", name: "Yeni" })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include(
          "code" => "target_reached", "current_value" => 150.0, "target_value" => 100.0, "progress_source" => "account"
        )
        expect(json["errors"]).to have_key("status")
        expect(goal.reload).to have_attributes(status: "abandoned", name: "Eski")
      end

      it "reopens an achieved goal together with a higher target" do
        goal = create(:goal, user: user, target_value: 10, current_value: 10, status: "achieved")

        json = patch_goal(goal, { status: "active", target_value: 20 })

        expect(response).to have_http_status(:ok)
        expect(json["goal"]).to include("status" => "active", "target_value" => 20.0, "progress_percent" => 50.0)
      end

      it "derives the status when none is sent: a higher target reopens an achieved goal" do
        goal = create(:goal, user: user, target_value: 10, current_value: 10, status: "achieved")

        expect(patch_goal(goal, { target_value: 40 })["goal"]["status"]).to eq("active")
      end

      it "derives the status when none is sent: reaching the target achieves it" do
        goal = create(:goal, user: user, target_value: 10, current_value: 2)

        expect(patch_goal(goal, { current_value: 10 })["goal"]["status"]).to eq("achieved")
      end

      it "keeps an abandoned goal abandoned when other fields change" do
        goal = create(:goal, user: user, target_value: 10, current_value: 10, status: "abandoned")

        expect(patch_goal(goal, { name: "Yine de bırakıldı" })["goal"]["status"]).to eq("abandoned")
      end

      it "marks a manual goal achieved when its progress is set to the target in the same request" do
        goal = create(:goal, user: user, target_value: 25, current_value: 3)

        expect(patch_goal(goal, { status: "achieved", current_value: 25 })["goal"])
          .to include("status" => "achieved", "current_value" => 25.0)
      end

      it "refuses achieved below the target, saving nothing" do
        goal = create(:goal, user: user, name: "Yarım", target_value: 25, current_value: 3)

        json = patch_goal(goal, { status: "achieved", name: "Bitti mi?" })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("code" => "target_not_reached", "current_value" => 3.0, "target_value" => 25.0,
                                "progress_source" => "manual")
        expect(goal.reload).to have_attributes(status: "active", name: "Yarım")
      end

      it "422s with validation_failed for an unknown status" do
        goal = create(:goal, user: user)

        json = patch_goal(goal, { status: "done" })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("validation_failed")
        expect(json["details"]["status"]).to eq([ { "error" => "inclusion", "value" => "done" } ])
      end

      it "422s with invalid_parameter for a status that is not a string" do
        goal = create(:goal, user: user, target_value: 10, current_value: 10, status: "achieved")

        expect(patch_goal(goal, { status: [ "active" ] })).to include("code" => "invalid_parameter", "param" => "status")
        expect(goal.reload.status).to eq("achieved")
      end
    end

    describe "linking an account or a habit after creation" do
      it "links a habit to a habit goal and counts its completed days" do
        habit = create(:habit, user: user, name: "Okuma")
        3.times { |n| create(:habit_log, habit: habit, date: Date.current - n) }
        goal = create(:goal, user: user, target_type: "habit", target_value: 30, current_value: 0)

        json = patch_goal(goal, { related: "Habit-#{habit.id}" })

        expect(response).to have_http_status(:ok)
        expect(json["goal"]).to include("current_value" => 3.0, "progress_source" => "habit")
        expect(json["goal"]["related"]).to include("type" => "Habit", "id" => habit.id, "name" => "Okuma")
        expect(goal.reload.related).to eq(habit)
      end

      it "relinks a financial goal to another account" do
        first = create(:account, user: user, initial_balance_cents: 10_00)
        second = create(:account, user: user, initial_balance_cents: 70_00)
        goal = create(:goal, user: user, target_type: "financial", related: first, target_value: 100)

        json = patch_goal(goal, { related: "Account-#{second.id}" })

        expect(json["goal"]).to include("current_value" => 70.0)
        expect(json["goal"]["related"]).to include("type" => "Account", "id" => second.id)
      end

      it "accepts an archived habit, as the web does" do
        habit = create(:habit, user: user, archived_at: 1.day.ago)
        goal = create(:goal, user: user, target_type: "habit")

        expect(patch_goal(goal, { related: "Habit-#{habit.id}" })["goal"]["related"]["id"]).to eq(habit.id)
      end

      it "unlinks with null, \"\" or \"none\"" do
        habit = create(:habit, user: user)

        [ nil, "", "none" ].each do |value|
          goal = create(:goal, user: user, target_type: "habit", related: habit)
          json = patch_goal(goal, { related: value })
          expect(json["goal"]).to include("related" => nil, "progress_source" => "manual"), "for #{value.inspect}"
          expect(goal.reload.related).to be_nil
        end
      end

      it "keeps the habit's count at the moment it is unlinked, even if the goal was not read since" do
        habit = create(:habit, user: user)
        goal = create(:goal, user: user, target_type: "habit", related: habit, target_value: 10, current_value: 0)
        2.times { |n| create(:habit_log, habit: habit, date: Date.current - n) }

        json = patch_goal(goal, { related: "none" })

        expect(json["goal"]).to include("current_value" => 2.0, "progress_source" => "manual", "related" => nil)
      end

      it "edits a goal whose linked account is overdrawn" do
        account = create(:account, user: user, account_type: "credit_card", initial_balance_cents: -500_00)
        goal = create(:goal, user: user, target_type: "financial", related: account, target_value: 100)

        json = patch_goal(goal, { name: "Borcu kapat" })

        expect(response).to have_http_status(:ok)
        expect(json["goal"]).to include("name" => "Borcu kapat", "current_value" => -500.0, "status" => "active")
      end

      it "lets a manual value sent with the unlink win" do
        habit = create(:habit, user: user)
        goal = create(:goal, user: user, target_type: "habit", related: habit, target_value: 10)
        create(:habit_log, habit: habit)

        expect(patch_goal(goal, { related: nil, current_value: 7 })["goal"]["current_value"]).to eq(7.0)
      end

      it "keeps the link when related is not sent" do
        account = create(:account, user: user)
        goal = create(:goal, user: user, target_type: "financial", related: account)

        patch_goal(goal, { name: "Yeni ad" })

        expect(goal.reload.related).to eq(account)
      end

      it "drops a link that no longer fits when the target type changes, keeping the value it had then" do
        account = create(:account, user: user, initial_balance_cents: 90_00)
        goal = create(:goal, user: user, target_type: "financial", related: account, target_value: 500, current_value: 0)

        json = patch_goal(goal, { target_type: "custom" })

        expect(json["goal"]).to include("target_type" => "custom", "related" => nil, "progress_source" => "manual")
        expect(json["goal"]["current_value"]).to eq(90.0)
      end

      it "422s with must_match_target_type for an account on a habit goal, saving nothing" do
        account = create(:account, user: user)
        goal = create(:goal, user: user, name: "Alışkanlık", target_type: "habit")

        json = patch_goal(goal, { related: "Account-#{account.id}", name: "Değişmedi mi?" })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("validation_failed")
        expect(json["details"]["related"]).to eq([ { "error" => "must_match_target_type" } ])
        expect(goal.reload).to have_attributes(related: nil, name: "Alışkanlık")
      end

      it "422s with must_match_target_type for any link on a custom goal, or a type change to a mismatched link" do
        habit = create(:habit, user: user)
        custom_goal = create(:goal, user: user, target_type: "custom")
        habit_goal = create(:goal, user: user, target_type: "habit")

        expect(patch_goal(custom_goal, { related: "Habit-#{habit.id}" })["details"]).to have_key("related")
        expect(custom_goal.reload.related).to be_nil

        json = patch_goal(habit_goal, { target_type: "financial", related: "Habit-#{habit.id}" })
        expect(json["details"]["related"]).to eq([ { "error" => "must_match_target_type" } ])
        expect(habit_goal.reload.target_type).to eq("habit")
      end

      it "404s for another user's habit or account, or one that does not exist, changing nothing" do
        account = create(:account, user: user)
        goal = create(:goal, user: user, target_type: "financial", related: account)

        [ "Habit-#{create(:habit).id}", "Account-#{create(:account).id}", "Account-0" ].each do |value|
          json = patch_goal(goal, { related: value })
          expect(response).to have_http_status(:not_found), "for #{value}"
          expect(json["code"]).to eq("not_found")
        end
        expect(goal.reload.related).to eq(account)
      end

      it "422s with invalid_parameter for a related value it cannot read" do
        goal = create(:goal, user: user)

        [ "Account", "Account-abc", "Todo-1", "account-1", 5 ].each do |value|
          json = patch_goal(goal, { related: value })
          expect(json).to include("code" => "invalid_parameter", "param" => "related"), "for #{value.inspect}"
        end
      end
    end

    describe "POST /api/v1/goals" do
      def post_goal(params)
        post api_v1_goals_path, headers: auth, params: params, as: :json
        body
      end

      it "returns the goal recomputed, with the status its progress implies" do
        account = create(:account, user: user, initial_balance_cents: 300_00)

        json = post_goal({ name: "Kasa", target_type: "financial", target_value: 200, related: "Account-#{account.id}" })

        expect(response).to have_http_status(:created)
        expect(json["goal"]).to include("status" => "achieved", "current_value" => 300.0, "progress_source" => "account")
      end

      it "defaults the unit to the user's currency" do
        user.update!(currency: "USD")

        expect(post_goal({ name: "Dolar", target_value: 10 })["goal"]["unit"]).to eq("USD")
      end

      it "creates an abandoned goal when asked" do
        expect(post_goal({ name: "Belki", target_value: 10, status: "abandoned" })["goal"]["status"]).to eq("abandoned")
      end

      it "422s with target_not_reached for an achieved goal below its target" do
        json = post_goal({ name: "Erken", target_value: 10, current_value: 2, status: "achieved" })

        expect(json["code"]).to eq("target_not_reached")
        expect(user.goals).to be_empty
      end

      it "422s with must_match_target_type for a custom goal with a link" do
        account = create(:account, user: user)

        json = post_goal({ name: "Özel", target_type: "custom", target_value: 10, related: "Account-#{account.id}" })

        expect(json["details"]["related"]).to eq([ { "error" => "must_match_target_type" } ])
        expect(user.goals).to be_empty
      end
    end

    describe "strict parameters on POST and PATCH" do
      let(:goal) { create(:goal, user: user, target_value: 100, current_value: 5) }

      it "422s with invalid_parameter for numbers it cannot read" do
        [ { target_value: "abc" }, { target_value: "" }, { current_value: "12,5" }, { current_value: true } ].each do |params|
          json = patch_goal(goal, params)
          expect(json).to include("code" => "invalid_parameter", "param" => params.keys.first.to_s), "for #{params.inspect}"
        end
        expect(goal.reload).to have_attributes(target_value: 100, current_value: 5)
      end

      it "accepts numbers sent as strings" do
        expect(patch_goal(goal, { target_value: "250.5" })["goal"]["target_value"]).to eq(250.5)
      end

      it "422s with value_out_of_range for a number decimal(14, 2) cannot hold" do
        json = patch_goal(goal, { target_value: 1_000_000_000_000 })

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["code"]).to eq("value_out_of_range")
      end

      it "422s with validation_failed for a negative or null value" do
        json = patch_goal(goal, { target_value: -1, current_value: -2 })

        expect(json["code"]).to eq("validation_failed")
        expect(json["details"]).to include(
          "target_value" => [ { "error" => "greater_than_or_equal_to", "value" => "-1.0", "count" => 0 } ],
          "current_value" => [ { "error" => "greater_than_or_equal_to", "count" => 0 } ]
        )

        expect(patch_goal(goal, { current_value: nil })["details"]["current_value"]).to eq([ { "error" => "not_a_number" } ])
      end

      it "422s with invalid_date for a deadline that is not YYYY-MM-DD, and clears it with null" do
        goal.update!(deadline: Date.current + 10)

        json = patch_goal(goal, { deadline: "2026-02-30" })
        expect(json).to include("code" => "invalid_date", "param" => "deadline")
        expect(goal.reload.deadline).to eq(Date.current + 10)

        expect(patch_goal(goal, { deadline: nil })["goal"]["deadline"]).to be_nil
      end

      it "422s with validation_failed for a color that is not #RRGGBB" do
        json = patch_goal(goal, { color: "red;background:url(x)" })

        expect(json["details"]["color"]).to eq([ { "error" => "invalid" } ])
      end
    end

    describe "PATCH /api/v1/goals/:id/update_progress" do
      it "422s with progress_computed for a goal whose value is computed, changing nothing" do
        account = create(:account, user: user, initial_balance_cents: 10_00)
        goal = create(:goal, user: user, target_type: "financial", related: account, target_value: 100, current_value: 10)

        patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 5 }, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body).to include("code" => "progress_computed", "progress_source" => "account")
        expect(goal.reload.current_value).to eq(10)
      end

      it "logs progress for a habit goal with no habit linked" do
        goal = create(:goal, user: user, target_type: "habit", target_value: 10, current_value: 2)

        patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 3 }, as: :json

        expect(body["goal"]).to include("current_value" => 5.0, "progress_source" => "manual")
      end

      it "422s with invalid_parameter for a delta it cannot read, changing nothing" do
        goal = create(:goal, user: user, current_value: 7)

        patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: "abc" }, as: :json

        expect(body).to include("code" => "invalid_parameter", "param" => "delta")
        expect(goal.reload.current_value).to eq(7)
      end

      it "422s with value_out_of_range past decimal(14, 2)" do
        goal = create(:goal, user: user, current_value: 999_999_999_999)

        patch update_progress_api_v1_goal_path(goal), headers: auth, params: { delta: 1 }, as: :json

        expect(body["code"]).to eq("value_out_of_range")
        expect(goal.reload.current_value).to eq(999_999_999_999)
      end
    end
  end
end
