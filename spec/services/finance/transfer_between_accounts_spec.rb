require 'rails_helper'

RSpec.describe Finance::TransferBetweenAccounts do
  let(:user) { create(:user) }
  let(:from) { create(:account, user: user, initial_balance_cents: 10_000_00) }
  let(:to)   { create(:account, user: user, initial_balance_cents: 0) }

  it "creates a transfer transaction" do
    result = described_class.call(user: user, from_account: from, to_account: to, amount_cents: 1_000_00)
    expect(result.success?).to be true
    expect(result.transaction.kind).to eq("transfer")
    expect(result.transaction.related_account).to eq(to)
  end

  it "rejects same-account transfer" do
    result = described_class.call(user: user, from_account: from, to_account: from, amount_cents: 100_00)
    expect(result.success?).to be false
  end

  it "rejects zero amount" do
    result = described_class.call(user: user, from_account: from, to_account: to, amount_cents: 0)
    expect(result.success?).to be false
  end
end
