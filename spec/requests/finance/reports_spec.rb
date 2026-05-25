require 'rails_helper'

RSpec.describe "Finance::Reports", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }
  let(:groceries) { create(:finance_category, user: user, name: "Groceries", kind: "expense") }

  before { sign_in user }

  describe "GET /finance/reports" do
    it "renders with default month range" do
      create(:transaction, user: user, account: account, finance_category: groceries, kind: "expense", amount_cents: 200_00)
      get finance_reports_path
      expect(response).to have_http_status(:success)
    end

    it "accepts custom from/to range" do
      get finance_reports_path, params: { from: 2.months.ago.to_date, to: Date.current }
      expect(response).to have_http_status(:success)
    end

    it "renders when there are no transactions in range" do
      get finance_reports_path
      expect(response).to have_http_status(:success)
    end
  end
end
