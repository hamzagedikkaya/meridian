require 'rails_helper'

RSpec.describe "QuickCaptures", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /quick_captures" do
    it "creates a todo for free text" do
      expect { post quick_captures_path, params: { text: "Buy milk" } }
        .to change(Todo, :count).by(1)
    end

    it "creates a transaction for numeric input" do
      create(:account, user: user)
      expect { post quick_captures_path, params: { text: "-42.50 Lunch" } }
        .to change(Transaction, :count).by(1)
    end

    it "rejects empty input" do
      post quick_captures_path, params: { text: "" }
      expect(flash[:alert]).to be_present
    end
  end
end
