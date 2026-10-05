# A VTIMEZONE component (RFC 5545 §3.6.5) for one IANA zone. The iCal feed
# gives a timed series' DTSTART as wall-clock time with this TZID, so a
# calendar app expands the RRULE in the user's zone, as
# Event#occurrences_between does: a Monday 01:00 series in Istanbul stays on
# Mondays instead of moving to the UTC day (Sunday 22:00).
#
# Every clock change from +from+ on is listed. A zone that still changes its
# clocks each year ends with one yearly observance per change when a rule
# (the nth or last weekday of a month, or a fixed day) fits the coming
# RULE_CHECK_YEARS; otherwise its changes are listed for EXPLICIT_YEARS more.
class IcalTimeZone
  RULE_CHECK_YEARS = 5
  EXPLICIT_YEARS = 30
  WEEKDAYS = %w[SU MO TU WE TH FR SA].freeze

  def initialize(zone, from:)
    @tz = zone.respond_to?(:tzinfo) ? zone.tzinfo : TZInfo::Timezone.get(zone.to_s)
    @from = from.utc
  end

  def tzid
    @tz.identifier
  end

  def to_ical
    rule_year = [ Time.current.year, @from.year ].max + 1
    rules = yearly_rules(rule_year)
    explicit_until = if rules || changes_in(rule_year).empty?
      Time.utc(rule_year)
    else
      Time.utc(rule_year + EXPLICIT_YEARS)
    end

    first = @tz.period_for(@from).offset
    lines = [ "BEGIN:VTIMEZONE", "TZID:#{tzid}" ]
    lines += observance(first, first, (@from + first.observed_utc_offset).strftime("%Y%m%dT%H%M%S"))
    @tz.transitions_up_to(explicit_until, @from).each do |change|
      lines += observance(change.previous_offset, change.offset, local_onset(change))
    end
    rules&.each do |change, rule|
      lines += observance(change.previous_offset, change.offset, local_onset(change), rule)
    end
    lines << "END:VTIMEZONE"
    lines.map { |line| "#{line}\r\n" }.join
  end

  private

  def changes_in(year)
    @tz.transitions_up_to(Time.utc(year + 1), Time.utc(year))
  end

  # The local time just before the change, which RFC 5545 gives an
  # observance's DTSTART in (with TZOFFSETFROM).
  def local_onset(change)
    change.local_end_at.to_time.strftime("%Y%m%dT%H%M%S")
  end

  # [[change, "FREQ=YEARLY;..."], ...] for +year+'s changes when each one
  # recurs by its rule over the following years, else nil.
  def yearly_rules(year)
    changes = changes_in(year)
    return nil if changes.empty?

    later = (1..RULE_CHECK_YEARS).map { |n| changes_in(year + n) }
    return nil unless later.all? { |list| list.size == changes.size }

    rules = changes.each_with_index.map do |change, index|
      rule = candidate_rules(change).find do |candidate|
        later.each_with_index.all? { |list, n| same_change?(list[index], change, candidate.date_for.call(year + n + 1)) }
      end
      rule && [ change, rule.text ]
    end
    rules.all? ? rules : nil
  end

  Candidate = Struct.new(:text, :date_for)

  def candidate_rules(change)
    local = change.local_end_at.to_time
    month = local.month
    weekday = WEEKDAYS[local.wday]
    nth = (local.day - 1) / 7 + 1
    [
      Candidate.new("FREQ=YEARLY;BYMONTH=#{month};BYDAY=#{nth}#{weekday}",
                    ->(year) { nth_weekday(year, month, local.wday, nth) }),
      Candidate.new("FREQ=YEARLY;BYMONTH=#{month};BYDAY=-1#{weekday}",
                    ->(year) { last_weekday(year, month, local.wday) }),
      Candidate.new("FREQ=YEARLY;BYMONTH=#{month};BYMONTHDAY=#{local.day}",
                    ->(year) { Date.new(year, month, local.day) if Date.valid_date?(year, month, local.day) })
    ]
  end

  def same_change?(other, change, date)
    return false unless other && date

    local = other.local_end_at.to_time
    first = change.local_end_at.to_time
    local.to_date == date && local.strftime("%H%M%S") == first.strftime("%H%M%S") &&
      other.offset.observed_utc_offset == change.offset.observed_utc_offset &&
      other.previous_offset.observed_utc_offset == change.previous_offset.observed_utc_offset
  end

  def nth_weekday(year, month, wday, nth)
    first = Date.new(year, month, 1)
    date = first + ((wday - first.wday) % 7) + (nth - 1) * 7
    date if date.month == month
  end

  def last_weekday(year, month, wday)
    last = Date.new(year, month, -1)
    last - ((last.wday - wday) % 7)
  end

  def observance(from_offset, to_offset, dtstart, rule = nil)
    kind = to_offset.dst? ? "DAYLIGHT" : "STANDARD"
    lines = [ "BEGIN:#{kind}", "DTSTART:#{dtstart}" ]
    lines << "RRULE:#{rule}" if rule
    lines << "TZOFFSETFROM:#{utc_offset(from_offset.observed_utc_offset)}"
    lines << "TZOFFSETTO:#{utc_offset(to_offset.observed_utc_offset)}"
    lines << "TZNAME:#{to_offset.abbreviation}" if to_offset.abbreviation.to_s.match?(/\A[\w+-]+\z/)
    lines << "END:#{kind}"
  end

  # RFC 5545 §3.3.14: ±hhmm, or ±hhmmss when the offset has seconds.
  def utc_offset(seconds)
    sign = seconds.negative? ? "-" : "+"
    hours, rest = seconds.abs.divmod(3600)
    minutes, secs = rest.divmod(60)
    format("%s%02d%02d%s", sign, hours, minutes, secs.zero? ? "" : format("%02d", secs))
  end
end
