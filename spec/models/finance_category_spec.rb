require 'rails_helper'

RSpec.describe FinanceCategory, type: :model do
  describe "validations" do
    subject { build(:finance_category) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:kind).in_array(described_class::KINDS) }
  end

  describe "scopes" do
    let(:user) { create(:user) }

    it "filters by kind" do
      inc = create(:finance_category, user: user, kind: "income")
      exp = create(:finance_category, user: user, kind: "expense")
      expect(described_class.income).to include(inc)
      expect(described_class.expense).to include(exp)
    end
  end
end
