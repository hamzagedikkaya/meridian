# How the iCal feed writes one series so that a calendar app, expanding it
# as RFC 5545 says, gets the days Event#occurrences_between lists (ice_cube's
# reading of the same rule). The two readings differ in two ways, bridged
# here:
#
# - RFC 5545 counts DTSTART as the first instance even when the rule does
#   not match it (a Monday/Wednesday series started on a Sunday, the phone's
#   "every weekday" started on a Saturday); ice_cube lists only the days the
#   rule matches. The feed's DTSTART is the series' first real occurrence.
# - A MONTHLY or YEARLY rule that takes its day from the start (no BYDAY or
#   BYMONTHDAY) on the 29th to 31st: ice_cube moves it to a shorter month's
#   last day (31 January, 28 February, 31 March), RFC 5545 skips that month.
#   The rule spells the day out as "the latest of the 28th to the start's
#   day" (BYMONTHDAY=28,29,30;BYSETPOS=-1, or BYMONTHDAY=-1 for the 31st).
#   BYSETPOS picks one day per FREQ period, so a YEARLY rule in several
#   months becomes FREQ=MONTHLY (the same days), or, every other year or
#   less often, one RRULE per month; with COUNT as well, which several rules
#   would each apply, its occurrences are listed (RDATE) instead.
class IcalRecurrence
  # Windows searched, in turn, for the first occurrence: most series occur
  # within a month, and none is saved without one within HORIZON.
  SEARCH_SPANS = [ 1.month, 1.year, RecurrenceRule::HORIZON ].freeze
  # The fewest days each month has (February in a common year).
  SHORTEST_MONTH = Hash.new(31).merge(2 => 28, 4 => 30, 6 => 30, 9 => 30, 11 => 30).freeze

  def initialize(event, rule)
    @event = event
    @parts = rule.parts
    @schedule = IceCube::Schedule.new(event.start_at)
    @schedule.add_recurrence_rule(rule.to_ice_cube)
  end

  # The first occurrence, at the start's wall clock; nil for a series that
  # never occurs (the server lists none of it).
  def first_start
    return @first_start if defined?(@first_start)

    start = @event.start_at
    @first_start = SEARCH_SPANS.lazy.filter_map { |span| @schedule.occurrences_between(start, start + span).first }.first
  end

  # The RRULE values to write: usually one, one per month for a YEARLY
  # series in several months every other year or less often, none when
  # #rdates lists the occurrences instead.
  def rules
    return [ text(@parts) ] unless month_end?

    day = { "BYMONTHDAY" => (anchor_day == 31 ? "-1" : (28..anchor_day).to_a.join(",")) }
    day["BYSETPOS"] = "-1" unless anchor_day == 31
    if @parts["FREQ"] == "MONTHLY"
      [ text(@parts.merge(day)) ]
    elsif months.one?
      [ text(@parts.merge("BYMONTH" => months.first.to_s).merge(day)) ]
    elsif interval == 1
      [ text(@parts.merge("FREQ" => "MONTHLY").merge(day)) ]
    elsif @parts.key?("COUNT")
      []
    else
      months.map { |month| text(@parts.merge("BYMONTH" => month.to_s).merge(day)) }
    end
  end

  # The occurrences after the first, when no rule is written (#rules is
  # empty): a COUNT series, so at most RecurrenceRule::MAX_COUNT of them.
  def rdates
    return [] if rules.any?

    @schedule.all_occurrences.drop(1)
  end

  private

  # Whether ice_cube moves some occurrence to a shorter month's last day.
  def month_end?
    %w[MONTHLY YEARLY].include?(@parts["FREQ"]) && !@parts.key?("BYDAY") && !@parts.key?("BYMONTHDAY") &&
      anchor_day >= 29 && months.any? { |month| SHORTEST_MONTH[month] < anchor_day }
  end

  def anchor_day
    @event.start_at.day
  end

  # The months the series occurs in: BYMONTH, else every month (MONTHLY) or
  # the start's (YEARLY).
  def months
    if @parts.key?("BYMONTH")
      @parts["BYMONTH"].split(",").map(&:to_i).uniq
    elsif @parts["FREQ"] == "MONTHLY"
      (1..12).to_a
    else
      [ @event.start_at.month ]
    end
  end

  def interval
    @parts.fetch("INTERVAL", "1").to_i
  end

  def text(parts)
    parts.map { |key, value| "#{key}=#{value}" }.join(";")
  end
end
