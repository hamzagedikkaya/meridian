require 'rails_helper'

RSpec.describe "Finance::Accounts", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /finance/accounts" do
    it "renders" do
      create(:account, user: user)
      get finance_accounts_path
      expect(response).to have_http_status(:success)
    end

    it "shows the total balance per currency for active accounts only" do
      create(:account, user: user, currency: "TRY", initial_balance_cents: 1_000_00)
      create(:account, user: user, currency: "TRY", initial_balance_cents: 500_00)
      create(:account, user: user, currency: "TRY", initial_balance_cents: 999_00, archived_at: Time.current)

      get finance_accounts_path

      expect(response.body).to include(I18n.t("finance.accounts.total_balance"))
      expect(response.body).to include(ApplicationController.helpers.money_format(1_500_00, currency: "TRY"))
    end
  end

  describe "GET /finance/accounts/new" do
    it "renders the new form" do
      get new_finance_account_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /finance/accounts" do
    it "creates an account with valid params" do
      expect {
        post finance_accounts_path, params: { account: { name: "Wallet", account_type: "cash", currency: "TRY", initial_balance_cents: 1000 } }
      }.to change(user.accounts, :count).by(1)
      expect(response).to redirect_to(finance_accounts_path)
    end

    it "re-renders new with invalid params" do
      post finance_accounts_path, params: { account: { name: "", account_type: "cash", currency: "TRY" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /finance/accounts/:id" do
    let(:account) { create(:account, user: user, name: "Old") }

    it "updates the account" do
      patch finance_account_path(account), params: { account: { name: "New" } }
      expect(account.reload.name).to eq("New")
      expect(response).to redirect_to(finance_accounts_path)
    end
  end

  describe "GET /finance/accounts/:id" do
    it "renders show with recent transactions" do
      account = create(:account, user: user)
      create(:transaction, user: user, account: account)
      get finance_account_path(account)
      expect(response).to have_http_status(:success)
    end
  end

  describe "DELETE /finance/accounts/:id" do
    it "destroys the account" do
      account = create(:account, user: user)
      expect { delete finance_account_path(account) }.to change(user.accounts, :count).by(-1)
    end
  end
end
