require 'rails_helper'

RSpec.describe Goals::CalculateProgress do
  let(:user) { create(:user) }

  describe ".call" do
    context "when target_type is \"financial\"" do
      context "when related is an Account" do
        it "uses the account balance (in major units) as the value" do
          account = create(:account, user: user, initial_balance_cents: 50_00)
          # +30.00 income, -10.00 expense → balance 70.00
          create(:transaction, :income, user: user, account: account, amount_cents: 30_00)
          create(:transaction, user: user, account: account, amount_cents: 10_00)
          goal = create(:goal, user: user, target_type: "financial", related: account,
                               target_value: 100, current_value: 0)

          result = described_class.call(goal)

          expect(result).to eq(70.0)
          expect(goal.reload.current_value).to eq(70.0)
        end

        it "marks the goal achieved once the balance meets the target" do
          account = create(:account, user: user, initial_balance_cents: 150_00)
          goal = create(:goal, user: user, target_type: "financial", related: account,
                               target_value: 100, current_value: 0, status: "active")

          described_class.call(goal)

          expect(goal.reload.current_value).to eq(150.0)
          expect(goal.status).to eq("achieved")
        end
      end

      context "when related is NOT an Account (nil)" do
        it "uses the user's total income (in major units) as the value" do
          create(:transaction, :income, user: user, amount_cents: 200_00)
          create(:transaction, :income, user: user, amount_cents: 50_00)
          # An expense should be ignored by the income scope.
          create(:transaction, user: user, amount_cents: 999_00)
          goal = create(:goal, user: user, target_type: "financial", related: nil,
                               target_value: 1000, current_value: 0)

          result = described_class.call(goal)

          expect(result).to eq(250.0)
          expect(goal.reload.current_value).to eq(250.0)
        end

        it "is zero when the user has no income transactions" do
          goal = create(:goal, user: user, target_type: "financial", related: nil,
                               target_value: 100, current_value: 0)

          expect(described_class.call(goal)).to eq(0.0)
          expect(goal.reload.current_value).to eq(0.0)
        end
      end
    end

    context "when target_type is \"habit\"" do
      context "when related is a Habit" do
        it "counts the habit's completed habit_logs" do
          habit = create(:habit, user: user)
          create(:habit_log, habit: habit, date: Date.current,       completed: true)
          create(:habit_log, habit: habit, date: Date.current - 1,   completed: true)
          create(:habit_log, habit: habit, date: Date.current - 2,   completed: false)
          goal = create(:goal, user: user, target_type: "habit", related: habit,
                               target_value: 10, current_value: 0)

          result = described_class.call(goal)

          expect(result).to eq(2)
          expect(goal.reload.current_value).to eq(2)
        end

        it "marks the goal achieved once completed logs reach the target" do
          habit = create(:habit, user: user)
          create(:habit_log, habit: habit, date: Date.current,     completed: true)
          create(:habit_log, habit: habit, date: Date.current - 1, completed: true)
          create(:habit_log, habit: habit, date: Date.current - 2, completed: true)
          goal = create(:goal, user: user, target_type: "habit", related: habit,
                               target_value: 3, current_value: 0, status: "active")

          described_class.call(goal)

          expect(goal.reload.current_value).to eq(3)
          expect(goal.status).to eq("achieved")
        end
      end

      context "when related is NOT a Habit" do
        it "leaves current_value unchanged" do
          goal = create(:goal, user: user, target_type: "habit", related: nil,
                               target_value: 10, current_value: 4)

          result = described_class.call(goal)

          expect(result).to eq(4)
          expect(goal.reload.current_value).to eq(4)
        end
      end
    end

    context "when target_type is \"custom\"" do
      it "uses the goal's existing current_value" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 100, current_value: 42)

        result = described_class.call(goal)

        expect(result).to eq(42)
        expect(goal.reload.current_value).to eq(42)
      end
    end

    describe "status transitions" do
      it "becomes \"achieved\" when value >= target_value" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 50, current_value: 50, status: "active")

        described_class.call(goal)

        expect(goal.reload.status).to eq("achieved")
      end

      it "stays \"active\" when value < target_value" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 100, current_value: 99, status: "active")

        described_class.call(goal)

        expect(goal.reload.status).to eq("active")
      end

      it "keeps an \"abandoned\" goal abandoned even when value meets the target" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 50, current_value: 100, status: "abandoned")

        described_class.call(goal)

        expect(goal.reload.status).to eq("abandoned")
      end

      it "keeps an \"abandoned\" goal abandoned when value is below the target" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 100, current_value: 10, status: "abandoned")

        described_class.call(goal)

        expect(goal.reload.status).to eq("abandoned")
      end
    end

    describe "persistence" do
      it "persists current_value and status via update_columns (skips validations/callbacks)" do
        account = create(:account, user: user, initial_balance_cents: 80_00)
        goal = create(:goal, user: user, target_type: "financial", related: account,
                             target_value: 50, current_value: 0, status: "active")

        # update_columns writes directly and does not run validations.
        allow(goal).to receive(:save)
        described_class.call(goal)
        expect(goal).not_to have_received(:save)

        goal.reload
        expect(goal.current_value).to eq(80.0)
        expect(goal.status).to eq("achieved")
      end

      it "returns the computed value" do
        goal = create(:goal, user: user, target_type: "custom",
                             target_value: 100, current_value: 17)

        expect(described_class.call(goal)).to eq(17)
      end
    end
  end
end
