require 'rails_helper'

RSpec.describe Tagging, type: :model do
  let(:user) { create(:user) }
  let(:tag) { create(:tag, user: user) }
  let(:todo) { create(:todo, user: user) }

  it "is valid with a tag and polymorphic taggable" do
    tagging = described_class.new(tag: tag, taggable: todo)
    expect(tagging).to be_valid
  end

  it "associates with the polymorphic taggable" do
    tagging = described_class.create!(tag: tag, taggable: todo)
    expect(tagging.taggable).to eq(todo)
    expect(tagging.taggable_type).to eq("Todo")
  end

  it "enforces uniqueness of tag within the same taggable" do
    described_class.create!(tag: tag, taggable: todo)
    duplicate = described_class.new(tag: tag, taggable: todo)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:tag_id]).to be_present
  end

  it "allows the same tag on different taggables" do
    other_todo = create(:todo, user: user)
    described_class.create!(tag: tag, taggable: todo)
    expect(described_class.new(tag: tag, taggable: other_todo)).to be_valid
  end
end
