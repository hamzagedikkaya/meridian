require 'rails_helper'

RSpec.describe Finance::ProcessSubscriptions do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }

  it "materializes a due subscription and advances the date" do
    sub = create(:subscription, user: user, account: account, frequency: "monthly",
                                amount_cents: 99_00, next_charge_on: 2.days.ago.to_date)
    expect {
      described_class.call(scope: Subscription.where(id: sub.id))
    }.to change(Transaction, :count).by(1)

    sub.reload
    expect(sub.next_charge_on).to be > Date.current
  end

  it "skips subscriptions whose next_charge_on is in the future" do
    create(:subscription, user: user, account: account, next_charge_on: 5.days.from_now.to_date)
    expect { described_class.call }.not_to change(Transaction, :count)
  end

  it "creates multiple transactions when several charge cycles are overdue" do
    sub = create(:subscription, user: user, account: account, frequency: "monthly",
                                amount_cents: 50_00, next_charge_on: 3.months.ago.to_date)
    expect {
      described_class.call(scope: Subscription.where(id: sub.id))
    }.to change(Transaction, :count).by_at_least(3)
  end

  it "is idempotent on a second pass" do
    create(:subscription, user: user, account: account, next_charge_on: 1.day.ago.to_date)
    described_class.call
    count_after_first = Transaction.count
    described_class.call
    expect(Transaction.count).to eq(count_after_first)
  end

  describe ".charge!" do
    let(:category) { create(:finance_category, user: user) }
    let(:sub) do
      create(:subscription, user: user, account: account, finance_category: category, name: "Spotify",
                            amount_cents: 60_00, frequency: "weekly", next_charge_on: Date.new(2026, 7, 3))
    end

    it "records one expense on the due date and moves the next charge one period on" do
      transaction = described_class.charge!(sub)

      expect(transaction).to have_attributes(
        user: user, account: account, finance_category: category, kind: "expense", amount_cents: 60_00,
        description: "Spotify", date: Date.new(2026, 7, 3), recurring: true
      )
      expect(sub.reload.next_charge_on).to eq(Date.new(2026, 7, 10))
    end

    it "takes another date for the expense" do
      expect(described_class.charge!(sub, date: Date.new(2026, 7, 1)).date).to eq(Date.new(2026, 7, 1))
    end

    it "saves neither the expense nor the new date when the expense is refused" do
      sub.update_column(:finance_category_id, create(:finance_category, user: user, kind: "income").id)

      expect { described_class.charge!(sub.reload) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Transaction.count).to eq(0)
      expect(sub.reload.next_charge_on).to eq(Date.new(2026, 7, 3))
    end
  end
end
