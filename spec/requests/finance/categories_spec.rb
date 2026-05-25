require 'rails_helper'

RSpec.describe "Finance::Categories", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /finance/categories" do
    it "renders" do
      get finance_categories_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /finance/categories/new" do
    it "renders the new form" do
      get new_finance_category_path
      expect(response).to have_http_status(:success)
    end

    it "respects the kind query param" do
      get new_finance_category_path(kind: "income")
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /finance/categories" do
    it "creates a category with valid params" do
      expect {
        post finance_categories_path, params: { finance_category: { name: "Bills", kind: "expense", color: "#A09B8E" } }
      }.to change(user.finance_categories, :count).by(1)
      expect(response).to redirect_to(finance_categories_path)
    end

    it "re-renders new with invalid params" do
      post finance_categories_path, params: { finance_category: { name: "", kind: "expense" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /finance/categories/:id" do
    let(:category) { create(:finance_category, user: user, name: "Old") }

    it "updates the category" do
      patch finance_category_path(category), params: { finance_category: { name: "New" } }
      expect(category.reload.name).to eq("New")
    end
  end

  describe "DELETE /finance/categories/:id" do
    it "destroys the category" do
      category = create(:finance_category, user: user)
      expect { delete finance_category_path(category) }.to change(user.finance_categories, :count).by(-1)
    end
  end
end
