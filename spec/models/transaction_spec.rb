require 'rails_helper'

RSpec.describe Transaction, type: :model do
  describe "validations" do
    subject { build(:transaction) }

    it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }
    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }
  end

  describe "transfer validation" do
    let(:user) { create(:user) }

    it "requires related_account for transfers" do
      t = build(:transaction, user: user, kind: "transfer", finance_category: nil)
      expect(t).not_to be_valid
      expect(t.errors.details[:related_account_id]).to include(error: :required_for_transfer)
      expect(t.errors[:related_account_id]).to include("must be present for transfers")
    end
  end

  describe "category kind validation" do
    let(:user) { create(:user) }

    it "rejects mismatched category kind" do
      inc_cat = create(:finance_category, user: user, kind: "income")
      t = build(:transaction, user: user, kind: "expense", finance_category: inc_cat)
      expect(t).not_to be_valid
      expect(t.errors.details[:finance_category]).to include(error: :kind_mismatch)
      expect(I18n.with_locale(:tr) { t.errors.full_messages_for(:finance_category) })
        .to eq([ "Kategori türü işlem türüyle aynı olmalı" ])
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:this_month) { create(:transaction, user: user, date: Date.current) }
    let!(:last_year)  { create(:transaction, user: user, date: 13.months.ago.to_date) }

    it ".this_month limits to current month" do
      expect(described_class.this_month).to include(this_month)
      expect(described_class.this_month).not_to include(last_year)
    end
  end
end
