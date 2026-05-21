require 'rails_helper'

RSpec.describe Account, type: :model do
  describe "validations" do
    subject { build(:account) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:account_type).in_array(described_class::ACCOUNT_TYPES) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:transactions).dependent(:destroy) }
    it { is_expected.to have_many(:subscriptions).dependent(:destroy) }
  end

  describe "#balance_cents" do
    let(:user)    { create(:user) }
    let(:account) { create(:account, user: user, initial_balance_cents: 1_000_00) }
    let(:cat_inc) { create(:finance_category, user: user, kind: "income") }
    let(:cat_exp) { create(:finance_category, user: user, kind: "expense") }

    it "returns initial balance when no transactions" do
      expect(account.balance_cents).to eq(1_000_00)
    end

    it "adds incomes and subtracts expenses" do
      create(:transaction, user: user, account: account, finance_category: cat_inc, kind: "income",  amount_cents: 500_00)
      create(:transaction, user: user, account: account, finance_category: cat_exp, kind: "expense", amount_cents: 200_00)
      expect(account.balance_cents).to eq(1_300_00)
    end
  end

  describe ".active scope" do
    let(:user) { create(:user) }

    it "excludes archived accounts" do
      live      = create(:account, user: user)
      _archived = create(:account, user: user, archived_at: Time.current)
      expect(described_class.active).to contain_exactly(live)
    end
  end

  describe "#archived?" do
    it "is true when archived_at is set" do
      expect(build(:account, archived_at: Time.current)).to be_archived
    end
  end
end
