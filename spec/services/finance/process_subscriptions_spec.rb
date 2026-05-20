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
end
