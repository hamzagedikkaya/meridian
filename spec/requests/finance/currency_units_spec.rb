require "rails_helper"

# Web finance forms in an account's own minor units (GAU: 1 unit per gram),
# the currency lock, account deletes and calendar dates west of UTC.
RSpec.describe "Web finance amounts and accounts", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:gold) { create(:account, user: user, currency: "GAU", name: "Altın") }
  let(:wallet) { create(:account, user: user, currency: "TRY", name: "Cüzdan") }

  before { sign_in user }

  def amount_input
    Nokogiri::HTML(response.body).at_css("input[name$='[amount]']")
  end

  describe "transactions" do
    let(:transaction) { create(:transaction, user: user, account: gold, amount_cents: 250, description: "Bilezik") }

    it "prefills a GAU amount in grams" do
      get edit_finance_transaction_path(transaction)

      expect(amount_input["value"]).to eq("250.0")
    end

    it "keeps the amount when the form is saved back unchanged" do
      get edit_finance_transaction_path(transaction)
      amount = amount_input["value"]

      patch finance_transaction_path(transaction), params: { transaction: { amount: amount, description: "renamed" } }

      expect(transaction.reload).to have_attributes(amount_cents: 250, description: "renamed")
    end

    it "still prefills TRY in lira" do
      try_row = create(:transaction, user: user, account: wallet, amount_cents: 12_50)

      get edit_finance_transaction_path(try_row)

      expect(amount_input["value"]).to eq("12.5")
    end

    it "refuses a fraction of a gram instead of rounding it" do
      patch finance_transaction_path(transaction), params: { transaction: { amount: "1.5" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("quick_capture.invalid_amount.too_precise", currency: "GAU")))
      expect(transaction.reload.amount_cents).to eq(250)
    end

    # The field showed the rounded "2.0", which one more click saved.
    it "shows the refused amount as typed, not rounded" do
      post finance_transactions_path, params: { transaction: { account_id: gold.id, kind: "expense", amount: "1.5", date: Date.current } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(amount_input["value"]).to eq("1.5")
    end

    it "still shows the stored amount on a plain edit" do
      get edit_finance_transaction_path(transaction, transaction: { amount: "9" })

      expect(amount_input["value"]).to eq("250.0")
    end

    # BigDecimal reads these; rounding them raised FloatDomainError (a 500).
    it "refuses an infinite or NaN amount as unreadable" do
      %w[Infinity -Infinity NaN].each do |amount|
        post finance_transactions_path, params: { transaction: { account_id: wallet.id, kind: "expense", amount: amount, date: Date.current } }

        expect(response).to have_http_status(:unprocessable_content)
      end
      expect(Transaction.count).to eq(0)
    end

    it "refuses a new transaction with a fraction of a kuruş" do
      expect do
        post finance_transactions_path, params: { transaction: { account_id: wallet.id, kind: "expense", amount: "1.005", date: Date.current } }
      end.not_to change(Transaction, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "subscriptions" do
    let(:subscription) { create(:subscription, user: user, account: gold, amount_cents: 250) }

    it "prefills and saves back a GAU amount unchanged" do
      get edit_finance_subscription_path(subscription)
      expect(amount_input["value"]).to eq("250.0")

      patch finance_subscription_path(subscription), params: { subscription: { amount: amount_input["value"], name: "renamed" } }

      expect(subscription.reload).to have_attributes(amount_cents: 250, name: "renamed")
    end

    it "shows a refused amount as typed and refuses an infinite one" do
      patch finance_subscription_path(subscription), params: { subscription: { amount: "1.5" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(amount_input["value"]).to eq("1.5")

      patch finance_subscription_path(subscription), params: { subscription: { amount: "Infinity" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(subscription.reload.amount_cents).to eq(250)
    end

    it "shows the monthly total from Subscription#monthly_amount_cents" do
      create(:subscription, user: user, account: wallet, amount_cents: 12_00, frequency: "yearly")
      create(:subscription, user: user, account: wallet, amount_cents: 10_00, frequency: "monthly")

      get finance_subscriptions_path

      expect(controller.instance_variable_get(:@monthly_total_cents)).to eq(11_00)
    end
  end

  describe "accounts" do
    it "keeps the currency of an account that has transactions" do
      create(:transaction, user: user, account: wallet, amount_cents: 100_00)

      patch finance_account_path(wallet), params: { account: { currency: "GAU" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("api.errors.currency_locked")))
      expect(wallet.reload.currency).to eq("TRY")
    end

    it "changes the currency of an unused account, and lets a used one change only letter case" do
      patch finance_account_path(wallet), params: { account: { currency: "USD" } }
      expect(wallet.reload.currency).to eq("USD")

      create(:transaction, user: user, account: wallet)
      patch finance_account_path(wallet), params: { account: { currency: "usd", name: "Dolar" } }
      expect(wallet.reload).to have_attributes(currency: "usd", name: "Dolar")
    end

    it "unlinks goals that tracked a deleted account" do
      goal = create(:goal, user: user, target_type: "financial", related: wallet)

      delete finance_account_path(wallet)

      expect(goal.reload).to have_attributes(related_type: nil, related_id: nil)
    end
  end

  describe "dates west of UTC" do
    let(:user) { create(:user, timezone: "Pacific Time (US & Canada)") }

    around do |example|
      travel_to(Time.find_zone("Pacific Time (US & Canada)").local(2026, 7, 15, 12)) { example.run }
    end

    it "puts a transaction on the 1st of a month in that month on the dashboard chart" do
      create(:transaction, :income, user: user, account: wallet, amount_cents: 500_00, date: Date.new(2026, 7, 1))

      get finance_root_path

      series = controller.instance_variable_get(:@six_month_series)
      expect(series[:labels].last).to eq("Jul")
      expect(series[:income].last).to eq(500.0)
      expect(series[:income][-2]).to eq(0.0)
    end

    it "keys the reports' daily totals by the transaction's own date" do
      create(:transaction, user: user, account: wallet, amount_cents: 50_00, date: Date.new(2026, 7, 1))

      get finance_reports_path

      expect(controller.instance_variable_get(:@daily_totals).keys).to eq([ I18n.l(Date.new(2026, 7, 1), format: "%d %b") ])
    end
  end
end
