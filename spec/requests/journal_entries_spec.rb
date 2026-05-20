require 'rails_helper'

RSpec.describe "Journal", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /journal" do
    it "renders" do
      get journal_entries_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /journal" do
    it "creates an entry" do
      expect {
        post journal_entries_path, params: { journal_entry: { date: Date.current, title: "Test", mood: "good" } }
      }.to change(JournalEntry, :count).by(1)
    end
  end
end
