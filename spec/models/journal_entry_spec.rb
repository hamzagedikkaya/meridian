require 'rails_helper'

RSpec.describe JournalEntry, type: :model do
  describe "validations" do
    subject { build(:journal_entry) }

    it { is_expected.to validate_presence_of(:date) }
    it { is_expected.to validate_inclusion_of(:mood).in_array(described_class::MOODS).allow_nil }
    it { is_expected.to validate_inclusion_of(:energy_level).in_range(1..5).allow_nil }
  end

  describe "#tag_list" do
    it "splits comma-separated tags" do
      entry = build(:journal_entry, tags: "work, reflection,  weekend")
      expect(entry.tag_list).to eq(%w[work reflection weekend])
    end
  end

  describe "#mood_emoji" do
    it "returns the emoji for the mood" do
      expect(build(:journal_entry, mood: "great").mood_emoji).to eq("😄")
    end
  end

  describe ".current_streak_for" do
    let(:user) { create(:user) }

    it "is 0 with no entries" do
      expect(described_class.current_streak_for(user)).to eq(0)
    end

    it "counts consecutive days ending today" do
      [ 0, 1, 2 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(3)
    end

    it "ignores entries dated after today" do
      [ 0, 1 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      create(:journal_entry, user: user, date: Date.current + 5)

      expect(described_class.current_streak_for(user)).to eq(2)
    end

    it "still counts when today isn't journaled yet but yesterday is" do
      [ 1, 2 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(2)
    end

    it "treats multiple entries on one day as a single day" do
      create(:journal_entry, user: user, date: Date.current)
      create(:journal_entry, user: user, date: Date.current)
      create(:journal_entry, user: user, date: Date.current - 1)
      expect(described_class.current_streak_for(user)).to eq(2)
    end

    it "is 0 when the most recent entry is older than yesterday" do
      create(:journal_entry, user: user, date: Date.current - 3)
      expect(described_class.current_streak_for(user)).to eq(0)
    end

    it "stops at the first gap" do
      [ 0, 1, 3, 4 ].each { |n| create(:journal_entry, user: user, date: Date.current - n) }
      expect(described_class.current_streak_for(user)).to eq(2)
    end
  end

  describe ".current_week_streak_for" do
    let(:user) { create(:user) }
    # A Wednesday; its week runs Monday 2026-10-05 to Sunday 2026-10-11.
    let(:today) { Date.new(2026, 10, 7) }

    def write_on(*dates)
      dates.each { |date| create(:journal_entry, user: user, date: date) }
    end

    it "is 0 with no entries" do
      expect(described_class.current_week_streak_for(user, today)).to eq(0)
    end

    it "counts consecutive Monday-to-Sunday weeks with an entry, ending this week" do
      write_on(Date.new(2026, 10, 5), Date.new(2026, 10, 4), Date.new(2026, 9, 28), Date.new(2026, 9, 24))
      expect(described_class.current_week_streak_for(user, today)).to eq(3)
    end

    it "still counts while this week has no entry yet but last week has" do
      write_on(Date.new(2026, 10, 4), Date.new(2026, 9, 22))
      expect(described_class.current_week_streak_for(user, today)).to eq(2)
    end

    it "is 0 when the latest entry is older than last week" do
      write_on(Date.new(2026, 9, 27))
      expect(described_class.current_week_streak_for(user, today)).to eq(0)
    end

    it "stops at the first week without an entry and ignores entries dated after today" do
      write_on(Date.new(2026, 10, 6), Date.new(2026, 9, 29), Date.new(2026, 9, 15), Date.new(2026, 10, 20))
      expect(described_class.current_week_streak_for(user, today)).to eq(2)
    end

    it "counts only the user's own entries" do
      create(:journal_entry, date: today)
      expect(described_class.current_week_streak_for(user, today)).to eq(0)
    end
  end

  describe "plain-text body" do
    it "stores text as one Trix-style block, escaping HTML" do
      expect(described_class.html_from_text("a <b> & c\r\nd\r\n\r\ne")).to eq("<div>a &lt;b&gt; &amp; c<br>d<br><br>e</div>")
      expect(described_class.html_from_text("  \n ")).to eq("")
      expect(described_class.html_from_text(nil)).to eq("")
    end

    it "reads back what was written" do
      entry = create(:journal_entry, body_text: "Bir satır\nİki <i>satır</i>\n\n\nÜçüncü paragraf")

      expect(entry.reload.body_text).to eq("Bir satır\nİki <i>satır</i>\n\n\nÜçüncü paragraf")
      expect(entry.body_formatting).to eq([])
    end

    it "names the formatting a body has beyond text, paragraphs and line breaks" do
      html = "<h1>Başlık</h1><div><strong>a</strong><em>b</em><del>c</del><a href='https://x.test'>d</a><br></div>" \
             "<blockquote>e</blockquote><pre>f</pre><ol><li>g</li></ol><span>h</span>"
      entry = build(:journal_entry, body: html)

      expect(entry.body_formatting).to eq(%w[heading bold italic strikethrough link quote code list other])
    end

    it "treats paragraphs, blocks, line breaks and bare text as plain" do
      [ "<p>a</p><p>b<br>c</p>", "<div>a</div><div><div>b</div></div>", "a\n\nb", "" ].each do |html|
        expect(build(:journal_entry, body: html).body_formatting).to eq([]), "for #{html.inspect}"
      end
    end

    it "compares text ignoring line endings, trailing spaces and the web's non-breaking spaces" do
      entry = build(:journal_entry, body: "<div>a&nbsp; b<br><br>c</div>")

      expect(entry.same_body_text?("a  b \r\n\r\nc\n")).to be(true)
      expect(entry.same_body_text?("a b\n\nc")).to be(false)
    end
  end
end
