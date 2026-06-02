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

    it "roots returns only top-level categories" do
      root = create(:finance_category, user: user, kind: "expense", name: "Market")
      child = create(:finance_category, user: user, kind: "expense", name: "Temel İhtiyaç", parent: root)
      expect(described_class.roots).to include(root)
      expect(described_class.roots).not_to include(child)
    end
  end

  describe "subcategory rules" do
    let(:user) { create(:user) }
    let(:root) { create(:finance_category, user: user, kind: "expense", name: "Market") }

    it "allows attaching a child to a root category of the same kind" do
      child = build(:finance_category, user: user, kind: "expense", parent: root)
      expect(child).to be_valid
    end

    it "rejects parents of a different kind" do
      income_root = create(:finance_category, user: user, kind: "income")
      child = build(:finance_category, user: user, kind: "expense", parent: income_root)
      expect(child).to be_invalid
      expect(child.errors[:parent_id]).to be_present
    end

    it "rejects parents that belong to a different user" do
      other_user_root = create(:finance_category, kind: "expense")
      child = build(:finance_category, user: user, kind: "expense", parent: other_user_root)
      expect(child).to be_invalid
    end

    it "rejects setting itself as parent" do
      root.parent_id = root.id
      expect(root).to be_invalid
    end

    it "rejects choosing a subcategory as a parent (max 2 levels)" do
      child = create(:finance_category, user: user, kind: "expense", parent: root, name: "Temel")
      grandchild = build(:finance_category, user: user, kind: "expense", parent: child, name: "Süt")
      expect(grandchild).to be_invalid
      expect(grandchild.errors[:parent_id]).to be_present
    end

    it "rejects making a category with children into a subcategory" do
      another_root = create(:finance_category, user: user, kind: "expense", name: "Eğlence")
      create(:finance_category, user: user, kind: "expense", parent: root, name: "Temel")
      root.parent_id = another_root.id
      expect(root).to be_invalid
    end

    it "destroys children when the parent is destroyed" do
      create(:finance_category, user: user, kind: "expense", parent: root, name: "Temel")
      expect { root.destroy }.to change(described_class, :count).by(-2)
    end
  end
end
