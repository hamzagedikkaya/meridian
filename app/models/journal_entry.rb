class JournalEntry < ApplicationRecord
  MOODS = %w[great good neutral bad awful].freeze
  MOOD_EMOJI = { "great" => "😄", "good" => "🙂", "neutral" => "😐", "bad" => "🙁", "awful" => "😞" }.freeze

  # Elements a plain-text body is made of: blocks and line breaks.
  PLAIN_ELEMENTS = %w[div p br].freeze
  # The formatting the web's editor (Trix) can add, by element. Any other
  # element counts as "other".
  FORMATTING = {
    "strong" => "bold", "b" => "bold",
    "em" => "italic", "i" => "italic",
    "del" => "strikethrough", "s" => "strikethrough", "strike" => "strikethrough",
    "a" => "link",
    "h1" => "heading", "h2" => "heading", "h3" => "heading", "h4" => "heading", "h5" => "heading", "h6" => "heading",
    "blockquote" => "quote",
    "pre" => "code", "code" => "code",
    "ul" => "list", "ol" => "list", "li" => "list",
    "action-text-attachment" => "attachment", "figure" => "attachment", "figcaption" => "attachment", "img" => "attachment"
  }.freeze
  # C0 controls other than tab and line feed, and DEL. PostgreSQL cannot
  # store NUL, and HTML has no use for the rest.
  CONTROL_CHARACTERS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/

  belongs_to :user
  has_rich_text :body
  has_many_attached :attachments

  validates :date, presence: true
  validates :mood, inclusion: { in: MOODS }, allow_nil: true
  validates :energy_level, inclusion: { in: 1..5 }, allow_nil: true

  scope :recent, -> { order(date: :desc, created_at: :desc) }
  scope :by_month, ->(year, month) { where(date: Date.new(year, month, 1)..Date.new(year, month, 1).end_of_month) }

  # Consecutive-day journaling streak ending today (or yesterday if today
  # hasn't been journaled yet) — encourages the daily-writing habit. Counts
  # distinct entry dates, so multiple entries on one day still count as one.
  def self.current_streak_for(user, today = Date.current)
    # Entries dated after today are not part of a streak that ends today.
    dates = user.journal_entries.where(date: ..today).distinct.pluck(:date).compact.sort.reverse
    return 0 if dates.empty?

    cutoff = dates.include?(today) ? today : today - 1
    return 0 unless dates.first == cutoff

    streak = 1
    dates.each_cons(2) do |a, b|
      (a - b).to_i == 1 ? streak += 1 : break
    end
    streak
  end

  # Consecutive weeks (Monday to Sunday, Date.beginning_of_week) with at least
  # one entry, ending this week, or last week while this week has none yet:
  # the gentler weekly counterpart of current_streak_for. Entries dated after
  # today do not count.
  def self.current_week_streak_for(user, today = Date.current)
    weeks = user.journal_entries.where(date: ..today).distinct.pluck(:date)
                .map(&:beginning_of_week).uniq.sort.reverse
    this_week = today.beginning_of_week
    return 0 unless [ this_week, this_week - 7 ].include?(weeks.first)

    streak = 1
    weeks.each_cons(2) do |a, b|
      (a - b).to_i == 7 ? streak += 1 : break
    end
    streak
  end

  def mood_emoji
    MOOD_EMOJI[mood]
  end

  def tag_list
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  # The body as plain text, nothing cut: "\n" for a line break, a blank line
  # between paragraphs. Lists, quotes and attachments come out as ActionText
  # writes them ("• item", “quote”).
  def body_text
    body.to_plain_text
  end

  # Replaces the body with plain text, HTML escaped. Every line break becomes
  # a <br> inside one <div>, which is how the web's editor stores what is
  # typed into it: a blank line is a paragraph break, and the web opens the
  # result for editing exactly as it was written.
  def body_text=(text)
    self.body = self.class.html_from_text(text).presence
  end

  # What the body holds beyond text, line breaks and paragraphs, which
  # #body_text cannot carry: e.g. ["bold", "list"]. [] for a plain body.
  def body_formatting
    content = body.body
    return [] if content.blank?

    found = []
    content.fragment.source.traverse do |node|
      next unless node.element?
      next if PLAIN_ELEMENTS.include?(node.name)

      found << FORMATTING.fetch(node.name, "other")
    end
    found.uniq
  end

  # Whether +text+ says the same as the body, ignoring the line-ending style,
  # spaces at the ends of lines and blank space around the whole text.
  def same_body_text?(text)
    self.class.comparable_text(text) == self.class.comparable_text(body_text)
  end

  def self.html_from_text(text)
    text = normalize_text(text)
    return "" if text.empty?

    lines = text.split("\n", -1).map { |line| ERB::Util.html_escape(line) }
    "<div>#{lines.join("<br>")}</div>"
  end

  # Line endings as "\n", control characters dropped, blank space around the
  # whole text trimmed.
  def self.normalize_text(text)
    text.to_s.gsub(/\r\n?/, "\n").gsub(CONTROL_CHARACTERS, "").strip
  end

  # The web's editor keeps runs of spaces as non-breaking spaces.
  def self.comparable_text(text)
    normalize_text(text).tr("\u00A0", " ").gsub(/[ \t]+$/, "")
  end
end
