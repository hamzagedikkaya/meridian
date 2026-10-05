require 'rails_helper'

RSpec.describe Todo, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "validations" do
    subject { build(:todo) }

    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_inclusion_of(:priority).in_array(described_class::PRIORITIES) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe "#overdue?" do
    it "is true when due_at is past and not done" do
      t = build(:todo, due_at: 1.day.ago, status: "pending")
      expect(t).to be_overdue
    end

    it "is false when done" do
      t = build(:todo, due_at: 1.day.ago, status: "done")
      expect(t).not_to be_overdue
    end
  end

  describe "completed_at sync" do
    it "sets completed_at when marked done" do
      t = create(:todo, status: "pending")
      expect { t.update(status: "done") }.to change { t.completed_at }.from(nil)
    end

    it "clears completed_at when reopened" do
      t = create(:todo, status: "done")
      expect { t.update(status: "pending") }.to change { t.completed_at }.to(nil)
    end
  end

  describe "destroy" do
    # focus_sessions.todo_id has a foreign key; without the association the
    # delete raised ActiveRecord::InvalidForeignKey.
    it "keeps the todo's focus sessions, unlinked" do
      todo = create(:todo)
      session = create(:focus_session, user: todo.user, todo: todo)

      expect { todo.destroy! }.not_to raise_error
      expect(session.reload.todo_id).to be_nil
    end

    it "keeps its subtasks, without a parent" do
      parent = create(:todo)
      subtask = create(:todo, user: parent.user, parent: parent)

      parent.destroy!

      expect(subtask.reload.parent_id).to be_nil
    end
  end

  describe "date-only due dates" do
    it "are stored as 23:59:59 that day in the current zone" do
      Time.use_zone("Istanbul") do
        expect(described_class.end_of_due_day(Date.new(2026, 10, 5))).to eq(Time.utc(2026, 10, 5, 20, 59, 59))
      end
    end

    it "have no due_time, while a timed due has HH:MM" do
      Time.use_zone("Istanbul") do
        date_only = build(:todo, due_at: described_class.end_of_due_day(Date.new(2026, 10, 5)))
        timed = build(:todo, due_at: Time.zone.local(2026, 10, 5, 9, 30))

        expect([ date_only.due_date, date_only.due_time, date_only.due_date_only? ]).to eq([ Date.new(2026, 10, 5), nil, true ])
        expect([ timed.due_date, timed.due_time, timed.due_date_only? ]).to eq([ Date.new(2026, 10, 5), "09:30", false ])
        expect(build(:todo, due_at: nil).due_time).to be_nil
      end
    end

    it "are due today all day and only overdue once the day is over" do
      todo = create(:todo, due_at: described_class.end_of_due_day(Date.new(2026, 10, 5)))

      travel_to Time.zone.local(2026, 10, 5, 23, 30) do
        expect(described_class.due_today).to include(todo)
        expect(described_class.overdue).not_to include(todo)
      end
      travel_to Time.zone.local(2026, 10, 6, 0, 0, 1) do
        expect(described_class.overdue).to include(todo)
      end
    end
  end

  describe "scopes" do
    it ".undated is the open todos without a due date" do
      undated = create(:todo, due_at: nil)
      create(:todo, due_at: nil, status: "done")
      create(:todo, due_at: 1.day.from_now)

      expect(described_class.undated).to eq([ undated ])
    end

    it ".due_upcoming is the open todos due in the 7 days after today" do
      travel_to Time.zone.local(2026, 10, 4, 12) do
        tomorrow = create(:todo, due_at: Time.zone.local(2026, 10, 5, 0, 0))
        in_a_week = create(:todo, due_at: Time.zone.local(2026, 10, 11, 23, 59, 59))
        create(:todo, due_at: Time.zone.local(2026, 10, 4, 23))
        create(:todo, due_at: Time.zone.local(2026, 10, 12, 0, 0))
        create(:todo, due_at: Time.zone.local(2026, 10, 6), status: "done")

        expect(described_class.due_upcoming).to contain_exactly(tomorrow, in_a_week)
      end
    end
  end
end
