require 'rails_helper'

RSpec.describe Event, type: :model do
  describe "validations" do
    subject { build(:event) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:start_at) }
    it { is_expected.to validate_inclusion_of(:event_type).in_array(described_class::EVENT_TYPES) }
  end

  describe "end_at validation" do
    it "rejects end_at before start_at" do
      e = build(:event, start_at: Time.current, end_at: 1.hour.ago)
      expect(e).not_to be_valid
    end
  end
end
