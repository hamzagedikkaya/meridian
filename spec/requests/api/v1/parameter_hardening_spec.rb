require "rails_helper"

# Wrong-typed, malformed or hostile parameter values get the contract's
# answers (1.1, 1.6): dropped, cast, 404 or 422, never Rails' HTML 500.
RSpec.describe "API parameter hardening", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }
  let(:wallet) { create(:account, user: user, name: "Wallet") }
  let(:market) { create(:finance_category, user: user, name: "Market") }

  def body = JSON.parse(response.body)

  describe "GET /api/v1/transactions" do
    before { create(:transaction, user: user, account: wallet, finance_category: market, amount_cents: 5_00) }

    it "reads a page that is a list, an object or far too large as a page it can serve" do
      get "#{api_v1_transactions_path}?page[]=1", headers: auth
      expect(response).to have_http_status(:ok)
      expect(body["meta"]["page"]).to eq(1)

      get api_v1_transactions_path(page: "99999999999999999999"), headers: auth
      expect(response).to have_http_status(:ok)
      expect(body["meta"]["page"]).to eq(Api::V1::TransactionsController::MAX_PAGE)
      expect(body["transactions"]).to eq([])
    end

    it "drops kind, account_id, category_id, from and to sent as a list or an object" do
      [ "kind[a]=b", "kind[]=expense", "account_id[]=1", "category_id[a]=1", "from[]=a&to=b", "from=2026-01-01&to[x]=b" ].each do |query|
        get "#{api_v1_transactions_path}?#{query}", headers: auth

        expect(response).to have_http_status(:ok), "for #{query}"
        expect(body["meta"]["total_count"]).to eq(1), "for #{query}"
      end
    end
  end

  describe "NUL bytes" do
    it "422s with invalid_parameter, naming the parameter, on a write" do
      post api_v1_todos_path, params: { title: "a\u0000b" }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(body).to include("code" => "invalid_parameter", "param" => "title")
      expect(user.todos).to be_empty
    end

    it "422s with invalid_parameter for search queries and capture text" do
      get api_v1_search_path(q: "ab\u0000cd"), headers: auth
      expect(body).to include("code" => "invalid_parameter", "param" => "q")

      get api_v1_transactions_path(q: "ab\u0000cd"), headers: auth
      expect(body).to include("code" => "invalid_parameter", "param" => "q")

      post api_v1_quick_captures_path, params: { text: "süt\u0000al" }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_parameter", "param" => "text")
    end

    it "finds one inside a nested body" do
      patch api_v1_me_path, params: { user: { name: "a\u0000b" } }, headers: auth, as: :json

      expect(body).to include("code" => "invalid_parameter", "param" => "user")
    end

    it "still lets a journal body_text drop its control characters" do
      post api_v1_journal_entries_path, params: { body_text: "a\u0000b" }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(body["entry"]["body_text"]).to eq("ab")
    end
  end

  describe "ids in bodies" do
    it "422s with invalid_parameter for an id that is not a whole number or not a scalar, writing nothing" do
      requests = {
        "budget finance_category_id" => ->(value) { post api_v1_budgets_path, params: { finance_category_id: value, monthly_limit_cents: 1000 }, headers: auth, as: :json },
        "category parent_id" => ->(value) { post api_v1_finance_categories_path, params: { name: "Alt", kind: "expense", parent_id: value }, headers: auth, as: :json },
        "subscription account_id" => ->(value) { post api_v1_subscriptions_path, params: { name: "S", amount_cents: 100, account_id: value }, headers: auth, as: :json },
        "transaction account_id" => ->(value) { post api_v1_transactions_path, params: { kind: "expense", amount_cents: 100, date: Date.current, account_id: value }, headers: auth, as: :json }
      }

      requests.each do |name, request|
        [ "#{market.id}abc", 1.5, [ market.id ], { "id" => market.id } ].each do |value|
          request.call(value)

          expect(response).to have_http_status(:unprocessable_content), "#{name} = #{value.inspect}"
          expect(body["code"]).to eq("invalid_parameter"), "#{name} = #{value.inspect}"
        end
      end
      expect([ user.budgets.count, user.finance_categories.count, user.subscriptions.count, user.transactions.count ]).to eq([ 0, 1, 0, 0 ])
    end

    it "422s for a list id on PATCH too" do
      budget = create(:budget, user: user, finance_category: market)
      subscription = create(:subscription, user: user, account: wallet)

      patch api_v1_budget_path(budget), params: { finance_category_id: [ market.id ] }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_parameter", "param" => "finance_category_id")

      patch api_v1_finance_category_path(market), params: { parent_id: [ market.id ] }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_parameter", "param" => "parent_id")

      patch api_v1_subscription_path(subscription), params: { account_id: [ wallet.id ] }, headers: auth, as: :json
      expect(body).to include("code" => "invalid_parameter", "param" => "account_id")
    end

    it "404s for another user's transfer destination, on POST and PATCH" do
      other_account = create(:account)
      transaction = create(:transaction, user: user, account: wallet, finance_category: market)

      post api_v1_transactions_path, params: { kind: "transfer", amount_cents: 100, date: Date.current, account_id: wallet.id,
                                               related_account_id: other_account.id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)

      patch api_v1_transaction_path(transaction), params: { kind: "transfer", related_account_id: other_account.id }, headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
      expect(transaction.reload.related_account_id).to be_nil
    end

    it "404s for another user's category on PATCH /subscriptions" do
      subscription = create(:subscription, user: user, account: wallet)

      patch api_v1_subscription_path(subscription), params: { finance_category_id: create(:finance_category).id }, headers: auth, as: :json

      expect(response).to have_http_status(:not_found)
      expect(subscription.reload.finance_category_id).to be_nil
    end
  end

  describe "a budget color sent as a list or an object" do
    it "is dropped, keeping the custom color" do
      budget = create(:budget, user: user, finance_category: market, color: "#00FF00")

      [ [ "#FF0000" ], { "x" => "#FF0000" } ].each do |color|
        patch api_v1_budget_path(budget), params: { color: color }, headers: auth, as: :json

        expect(response).to have_http_status(:ok)
        expect(budget.reload.color).to eq("#00FF00")
      end
    end
  end

  describe "POST /api/v1/quick_captures" do
    it "treats text that is a list or an object as missing" do
      [ [ "süt al" ], { "a" => "süt al" } ].each do |text|
        post api_v1_quick_captures_path, params: { text: text }, headers: auth, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(body["code"]).to eq("empty")
      end
      expect(user.todos).to be_empty
    end

    it "refuses an `as` that is not one of the choices, blank text included" do
      [ "  ", false, [] ].each do |as|
        post api_v1_quick_captures_path, params: { text: "yarın dişçi", as: as }, headers: auth, as: :json

        expect(body).to include("code" => "invalid_parameter", "param" => "as"), "for #{as.inspect}"
      end
    end
  end

  describe "GET /api/v1/events" do
    it "ignores a from or to that is not exactly YYYY-MM-DD, using the default window" do
      travel_to Time.zone.local(2026, 10, 15, 12)
      create(:event, user: user, title: "Earlier", start_at: Date.current.beginning_of_month.beginning_of_day + 9.hours)
      create(:event, user: user, title: "Today", start_at: Time.current.change(hour: 23, min: 0))

      [ Date.current.strftime("%Y-%m"), Date.current.strftime("%G-W%V-%u"), Date.current.strftime("%Y%m%d") ].each do |from|
        get api_v1_events_path(from: from), headers: auth

        expect(body["events"].map { |e| e["title"] }).to eq([ "Today" ]), "for #{from}"
      end
    end
  end

  describe "unknown paths" do
    it "answer the API's JSON 404" do
      get "/api/v1/nonexistent", headers: auth
      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(body).to eq("error" => "not_found", "code" => "not_found")

      post "/api/v1/todos/1/unknown_action"
      expect(response).to have_http_status(:not_found)
      expect(body["code"]).to eq("not_found")
    end

    it "answer the JSON 404 for the bare /api/v1 too, with or without a slash" do
      [ "/api/v1", "/api/v1/" ].each do |path|
        get path
        expect(response).to have_http_status(:not_found), path
        expect(response.media_type).to eq("application/json"), path
        expect(body).to eq("error" => "not_found", "code" => "not_found")
      end

      delete "/api/v1", headers: auth
      expect(body["code"]).to eq("not_found")
    end
  end
end
