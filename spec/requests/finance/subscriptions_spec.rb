require 'rails_helper'

RSpec.describe "Finance::Subscriptions", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }

  before { sign_in user }

  describe "GET /finance/subscriptions" do
    it "renders with monthly and yearly totals computed" do
      create(:subscription, user: user, account: account, amount_cents: 100_00, frequency: "monthly")
      create(:subscription, user: user, account: account, amount_cents: 1_200_00, frequency: "yearly")
      get finance_subscriptions_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /finance/subscriptions/new" do
    it "renders the new form" do
      get new_finance_subscription_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /finance/subscriptions" do
    it "creates a subscription with valid params" do
      expect {
        post finance_subscriptions_path, params: {
          subscription: {
            name: "Netflix", amount: "89.99", frequency: "monthly",
            account_id: account.id, start_date: Date.current, next_charge_on: Date.current + 1.month, active: true
          }
        }
      }.to change(user.subscriptions, :count).by(1)
      expect(response).to redirect_to(finance_subscriptions_path)
    end

    it "converts amount to amount_cents" do
      post finance_subscriptions_path, params: {
        subscription: {
          name: "Spotify", amount: "59.99", frequency: "monthly",
          account_id: account.id, start_date: Date.current, next_charge_on: Date.current + 1.month, active: true
        }
      }
      expect(user.subscriptions.last.amount_cents).to eq(59_99)
    end

    it "re-renders new with invalid params" do
      post finance_subscriptions_path, params: { subscription: { name: "", frequency: "monthly", account_id: account.id, amount_cents: 0 } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /finance/subscriptions/:id" do
    it "renders show" do
      sub = create(:subscription, user: user, account: account)
      get finance_subscription_path(sub)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /finance/subscriptions/:id" do
    let(:sub) { create(:subscription, user: user, account: account, name: "Old") }

    it "updates the subscription" do
      patch finance_subscription_path(sub), params: { subscription: { name: "New" } }
      expect(sub.reload.name).to eq("New")
    end
  end

  describe "DELETE /finance/subscriptions/:id" do
    it "destroys the subscription" do
      sub = create(:subscription, user: user, account: account)
      expect { delete finance_subscription_path(sub) }.to change(user.subscriptions, :count).by(-1)
    end
  end
end
