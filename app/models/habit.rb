class Habit < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly].freeze

  belongs_to :user
  belongs_to :goal, optional: true
  # HabitLog has no callbacks, so one DELETE does what a destroy per log did.
  has_many :habit_logs, dependent: :delete_all
  # Habit goals whose progress counts this habit's completed days. Deleting
  # the habit unlinks them (related_type and related_id both become NULL)
  # instead of leaving them pointing at a row that no longer exists; they
  # keep the habit's final count and are logged by hand from then on.
  has_many :tracking_goals, class_name: "Goal", as: :related, dependent: :nullify, inverse_of: :related
  # Ahead of the dependent callbacks, while the logs still exist.
  before_destroy :settle_tracking_goals, prepend: true

  belongs_to_same_user :goal
  validates :name, presence: true, length: { maximum: 60 }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :target_count, numericality: { greater_than: 0 }

  # Raised by the log writers (#set_log_count!, #toggle_log!) for a habit
  # whose logs are frozen; +code+ is what #log_refusal returned.
  class LogRefused < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("habit log refused: #{code}")
    end
  end

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Batched streak calculation — one query for many habits instead of N.
  def self.streaks_for(habits)
    habit_ids = habits.map(&:id)
    return {} if habit_ids.empty?

    today = Date.current
    rows = HabitLog.where(habit_id: habit_ids, completed: true, date: ..today)
                   .order(date: :desc).pluck(:habit_id, :date)
    by_habit = rows.group_by(&:first).transform_values { |arr| arr.map(&:last) }

    habit_ids.index_with do |hid|
      dates = by_habit[hid] || []
      cutoff = dates.include?(today) ? today : today - 1.day
      relevant = dates.drop_while { |d| d > cutoff }
      next 0 if relevant.empty? || relevant.first != cutoff

      streak = 1
      relevant.each_cons(2) do |a, b|
        (a - b).to_i == 1 ? streak += 1 : break
      end
      streak
    end
  end

  def log_for(date)
    habit_logs.find_or_initialize_by(date: date)
  end

  def daily?
    frequency == "daily"
  end

  def archived?
    archived_at.present?
  end

  # The first day the habit can be logged: the day it was created, in the
  # current zone (the user's, during a request).
  def start_date
    created_at.to_date
  end

  # The last day the habit was in use: today, or the day it was archived.
  def last_active_date
    archived? ? [ archived_at.to_date, Date.current ].min : Date.current
  end

  # Why `date` cannot be logged, or nil when it can. The rules every client
  # follows, web and API:
  #
  # - :habit_archived: an archived habit keeps counting in goals and history,
  #   so its logs are frozen;
  # - :future_date: the day has not happened yet;
  # - :before_habit_start: the habit did not exist on that day.
  def log_refusal(date)
    if archived? then :habit_archived
    elsif date > Date.current then :future_date
    elsif date < start_date then :before_habit_start
    end
  end

  # Puts the log for `date` into an explicit state instead of flipping it, so
  # a retried or duplicated request lands on the same result.
  #
  # Daily habits count within the day: 0..target_count, completed once the
  # target is reached. Weekly and monthly habits count *days* per period
  # (#period_completed_count), so a day is either done or not: any positive
  # count completes it and stores count = target_count, as the web checkbox
  # does. A count of 0 removes the log.
  #
  # Returns the saved log, or an unsaved empty one when it was removed.
  def set_log_count!(date, count)
    raise LogRefused, :habit_archived if archived?

    count = count.to_i.clamp(0, target_count)
    count = target_count if count.positive? && !daily?

    if count.zero?
      habit_logs.where(date: date).delete_all
      forget_first_logged_date
      return HabitLog.new(habit: self, date: date, count: 0, completed: false)
    end

    write_log!(date, count: count, completed: count >= target_count)
  end

  # The web and API toggle_today rules. With a delta (the +/- counter, only
  # for target_count > 1) the count moves within 0..target_count; otherwise
  # the day flips between done (count = target_count) and not done. A flip is
  # not idempotent by nature; clients that know the state they want should
  # use #set_log_count!. Refused for an archived habit, like #set_log_count!.
  def toggle_log!(date, delta: nil)
    raise LogRefused, :habit_archived if archived?

    log = habit_logs.find_by(date: date)

    if delta && target_count > 1
      count = (log&.count.to_i + delta).clamp(0, target_count)
      write_log!(date, count: count, completed: count >= target_count)
    else
      completed = !log&.completed?
      write_log!(date, count: completed ? target_count : 0, completed: completed)
    end
  end

  def completed_on?(date)
    habit_logs.where(date: date, completed: true).exists?
  end

  # Returns the current streak — consecutive days ending today (or yesterday if today not yet logged).
  def current_streak
    cutoff = completed_on?(Date.current) ? Date.current : Date.current - 1.day
    completed_dates = habit_logs.where(completed: true).where(date: ..cutoff).order(date: :desc).pluck(:date)
    return 0 if completed_dates.empty? || completed_dates.first != cutoff

    streak = 1
    completed_dates.each_cons(2) do |a, b|
      if (a - b).to_i == 1
        streak += 1
      else
        break
      end
    end
    streak
  end

  def longest_streak
    dates = habit_logs.where(completed: true).order(:date).pluck(:date)
    return 0 if dates.empty?

    longest = current = 1
    dates.each_cons(2) do |a, b|
      if (b - a).to_i == 1
        current += 1
        longest = current if current > longest
      else
        current = 1
      end
    end
    longest
  end

  # Share of the last `days` days, up to #last_active_date, that were
  # completed. Only days the habit existed count (#tracked_window): a habit
  # created today and done today is at 100%, not 1 of 30.
  def completion_rate(days: 30)
    range = tracked_window(days: days, end_date: last_active_date)
    completed = habit_logs.where(completed: true, date: range).count
    (completed.to_f / range.count * 100).round(1)
  end

  # The days of the `days`-long window ending on `end_date` that the habit
  # existed on: from its #start_date, or from an earlier logged day (logs
  # seeded or restored with their dates, or a start date that moved later
  # with the user's zone), and never before the window. Always holds
  # `end_date`. Days before it were not missed, so neither the chain nor the
  # completion rate shows or counts them.
  #
  # `first_logged` is the habit's earliest log date when the caller already
  # has it; otherwise #first_logged_date, which .first_logged_dates fills in
  # for a whole list in one query, and which is only read when the habit
  # starts inside the window.
  def tracked_window(days:, end_date: Date.current, first_logged: :lookup)
    from = end_date - (days - 1).days
    if start_date > from
      first_logged = first_logged_date if first_logged == :lookup
      from = [ start_date, first_logged, end_date ].compact.min if first_logged.nil? || first_logged > from
    end
    from..end_date
  end

  # The habit's earliest log date (nil without logs). .first_logged_dates
  # fills it in for a whole list in one query, so a list's chains and
  # completion rates do not look it up per habit; otherwise it is read
  # fresh. The log writers below forget a filled-in value.
  def first_logged_date
    return @first_logged_date if defined?(@first_logged_date)

    habit_logs.minimum(:date)
  end

  attr_writer :first_logged_date

  # Number of completed logs in the habit's current period — week for weekly
  # habits, month for monthly, the single day for daily. Used by the periodic
  # habits widget on /habits.
  def period_completed_count(today = Date.current)
    habit_logs.where(completed: true, date: period_range(today)).count
  end

  def period_complete?(today = Date.current)
    period_completed_count(today) >= target_count
  end

  def period_range(today = Date.current)
    case frequency
    when "weekly"  then today.beginning_of_week..today.end_of_week
    when "monthly" then today.beginning_of_month..today.end_of_month
    else                today..today
    end
  end

  # Returns the daily statuses for the "don't break the chain" visualisation.
  # Each element is `{ date:, status:, color: }` where status is one of
  # :completed, :partial, :missed, :today_pending. Oldest first → newest last.
  # When `trim: true` (default) the chain starts at the first :completed or
  # :partial entry — leading days with no progress are hidden so a brand-new
  # habit doesn't appear to have "missed" days it never could have done. If
  # there is no completed/partial entry at all, only today's link is returned.
  #
  # The window starts no earlier than the habit (#tracked_window): a habit
  # created three days ago has a four-day chain, untrimmed or not.
  def chain_window(days: 30, end_date: Date.current, trim: true)
    range = tracked_window(days: days, end_date: end_date)
    by_date = habit_logs.where(date: range).index_by(&:date)
    entries = range.map { |d| chain_entry_for(d, by_date[d], end_date) }
    trim ? trim_chain_leading(entries) : entries
  end

  # Batched chain window for the index page — one HabitLog query covering all
  # habits in the given window, then bucketed in memory. `end_date` may also
  # be a callable giving each habit its own last day (an archived habit's
  # archive day); the query then covers all of their windows.
  def self.chain_windows_for(habits, days: 14, end_date: Date.current, trim: true)
    return {} if habits.empty?

    ends = habits.to_h { |habit| [ habit, end_date.respond_to?(:call) ? end_date.call(habit) : end_date ] }
    window = (ends.values.min - (days - 1).days)..ends.values.max
    rows = HabitLog.where(habit_id: habits.map(&:id), date: window)
    by_habit = rows.group_by(&:habit_id).transform_values { |logs| logs.index_by(&:date) }
    # Back to 30 days, so the same lookup also serves #completion_rate.
    first_logged_dates(habits, [ window.begin, ends.values.min - 29 ].min)

    habits.index_with do |habit|
      bucket = by_habit[habit.id] || {}
      last = ends[habit]
      range = habit.tracked_window(days: days, end_date: last)
      entries = range.map { |d| habit.send(:chain_entry_for, d, bucket[d], last) }
      trim ? habit.send(:trim_chain_leading, entries) : entries
    end
  end

  # Week-to-date completion of `habits` (Home's habit figure), in percent:
  # their completed days from Monday through `today` over the days each of
  # them existed in that span (#tracked_window), so a habit added mid-week is
  # not behind for the days before it.
  def self.week_completion_pct(habits, today = Date.current)
    return 0 if habits.empty?

    week = today.beginning_of_week..today
    days = week.count
    first_logged_dates(habits, week.begin)
    possible = habits.sum { |habit| habit.tracked_window(days: days, end_date: today).count }
    completed = HabitLog.where(habit_id: habits.map(&:id), completed: true, date: week).count
    # Exact: 23 of 40 is 57.5, which a Float reads as 57.4999… and rounds to 57.
    (completed * 100r / possible).round
  end

  # Earliest log date of each habit in `habits` that started after `from`
  # (the others' windows are not clamped), in one query. Each such habit
  # also keeps its date (#first_logged_date), so its 30-day completion rate
  # does not look it up again.
  def self.first_logged_dates(habits, from)
    young = habits.select { |habit| habit.start_date > from }
    return {} if young.empty?

    dates = HabitLog.where(habit_id: young.map(&:id)).group(:habit_id).minimum(:date)
    young.each { |habit| habit.first_logged_date = dates[habit.id] }
    dates
  end
  private_class_method :first_logged_dates

  private

  def settle_tracking_goals
    tracking_goals.each(&:recalculate_progress!)
  end

  # One INSERT ... ON CONFLICT statement: two simultaneous first writes for
  # the same day cannot both insert and trip the unique (habit_id, date)
  # index, which used to surface as a 500.
  def write_log!(date, count:, completed:)
    HabitLog.upsert({ habit_id: id, date: date, count: count, completed: completed }, unique_by: %i[habit_id date])
    forget_first_logged_date
    habit_logs.find_by!(date: date)
  end

  def forget_first_logged_date
    remove_instance_variable(:@first_logged_date) if defined?(@first_logged_date)
  end

  def chain_entry_for(date, log, end_date)
    entry = { date: date, color: color }
    count = log&.count.to_i
    if log&.completed
      entry[:status] = :completed
    elsif count.positive? && count < target_count
      entry[:status] = :partial
      entry[:completed] = count
      entry[:possible] = target_count
    elsif date == Date.current && date == end_date
      entry[:status] = :today_pending
    else
      entry[:status] = :missed
    end
    entry
  end

  def trim_chain_leading(entries)
    start = entries.index { |e| [ :completed, :partial ].include?(e[:status]) }
    start.nil? ? [ entries.last ] : entries[start..]
  end
end
