# How an event repeats: the body of an RFC 5545 RRULE, for example
# "FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T205959Z". A recurring event is one
# row; its occurrences are expanded from this rule whenever events are read
# (Event#occurrences_between).
#
# Only rules Meridian can expand safely and faithfully are accepted:
#
# - At most one occurrence a day, at the event's own start time: FREQ is
#   DAILY, WEEKLY, MONTHLY or YEARLY, and BYHOUR, BYMINUTE and BYSECOND are
#   refused. SECONDLY or BYMINUTE would turn a single row into hundreds of
#   thousands of objects on every GET /events.
# - Parts ice_cube ignores or reads differently from RFC 5545 are refused
#   instead of being expanded into another series: BYSETPOS (ignored),
#   BYWEEKNO and BYYEARDAY, and BYDAY or BYMONTHDAY in a YEARLY rule without
#   BYMONTH (ice_cube keeps them to the start month: "FREQ=YEARLY;BYDAY=MO"
#   would be the Mondays of one month a year, where RFC 5545 means every
#   Monday of the year).
# - A rule that takes its day from the start (no BYMONTHDAY) on the 29th to
#   31st is moved to the month's last day in a shorter month (31 January,
#   28 February, 31 March), as ice_cube expands it; RFC 5545 would skip
#   those months, as an explicit BYMONTHDAY=31 does here too. The iCal feed
#   spells such a series out for calendar apps (IcalRecurrence).
# - INTERVAL and COUNT are 1..999, COUNT and UNTIL are not combined (RFC 5545
#   forbids it), and the rule is at most 500 characters.
class RecurrenceRule
  FREQUENCIES = %w[DAILY WEEKLY MONTHLY YEARLY].freeze
  PARTS = %w[FREQ INTERVAL COUNT UNTIL BYDAY BYMONTHDAY BYMONTH WKST].freeze
  WEEKDAYS = %w[MO TU WE TH FR SA SU].freeze
  MAX_INTERVAL = 999
  MAX_COUNT = 999
  # Every rule a picker builds is far shorter; a list of thousands of BYDAY
  # entries would be checked against every candidate day of every expansion.
  MAX_LENGTH = 500
  # A new or moved series must occur at least once within this time of its
  # start, so a rule that never matches (UNTIL before the start, 30 February)
  # does not save an event that no list would ever show.
  HORIZON = 10.years

  UNTIL_VALUE = /\A(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?\z/
  UTC_UNTIL = /\A\d{8}T\d{6}Z\z/
  NUMBER = /\A\d+\z/
  BYDAY_ITEM = /\A([+-]?[1-5])?(MO|TU|WE|TH|FR|SA|SU)\z/
  MONTH_DAY = /\A[+-]?\d{1,2}\z/

  Problem = Data.define(:type, :options)

  # Upper-cases the rule and drops an "RRULE:" prefix, whitespace and empty
  # parts. UNTIL becomes a UTC instant ("...T...Z"): a bare date is the end of
  # that day in +zone+ (RFC 5545 makes it the last day of the series), a time
  # without "Z" is the wall clock in +zone+. ice_cube would read both in the
  # server process's zone. nil for a blank rule.
  def self.normalize(value, zone: Time.zone)
    parts = value.to_s.gsub(/\s+/, "").upcase.delete_prefix("RRULE:").split(";").reject(&:empty?)
    parts.map! do |part|
      next part unless part.start_with?("UNTIL=")

      instant = utc_until(part.delete_prefix("UNTIL="), zone)
      instant ? "UNTIL=#{instant}" : part
    end
    parts.join(";").presence
  end

  def self.utc_until(value, zone)
    match = UNTIL_VALUE.match(value)
    return unless match

    year, month, day, hour, minute, second = match.captures.first(6).map { |part| part&.to_i }
    return unless Date.valid_date?(year, month, day)
    return if hour && (hour > 23 || minute > 59 || second > 59)

    time = if hour.nil?
      zone.local(year, month, day).change(hour: 23, min: 59, sec: 59)
    elsif match[7]
      Time.utc(year, month, day, hour, minute, second)
    else
      zone.local(year, month, day, hour, minute, second)
    end
    time.utc.strftime("%Y%m%dT%H%M%SZ")
  end
  private_class_method :utc_until

  attr_reader :problems

  def initialize(value, zone: Time.zone)
    @rule = self.class.normalize(value, zone: zone)
    @parts = {}
    @problems = []
    check
  end

  def valid?
    problems.empty?
  end

  # The rule's parts in their stored order ({"FREQ" => "WEEKLY", ...}).
  def parts
    @parts.dup
  end

  # The rule as ice_cube expands it. Weeks start on Monday unless WKST says
  # otherwise, as in RFC 5545 (ice_cube's own default is Sunday, which moves
  # the occurrences of an every-other-week rule).
  def to_ice_cube
    raise ArgumentError, "unsupported recurrence rule: #{@rule}" unless valid?

    IceCube::Rule.from_ical(@parts.key?("WKST") ? @rule : "#{@rule};WKST=MO")
  end

  # Whether a series anchored at +start_at+ occurs at least once within
  # HORIZON of it.
  def occurs_from?(start_at)
    schedule = IceCube::Schedule.new(start_at)
    schedule.add_recurrence_rule(to_ice_cube)
    schedule.occurs_between?(start_at, start_at + HORIZON)
  end

  private

  def check
    return problem(:invalid) if @rule.nil?
    return problem(:too_long, count: MAX_LENGTH) if @rule.length > MAX_LENGTH
    return problem(:invalid) unless read_parts

    unsupported = @parts.keys - PARTS
    return problem(:unsupported_part, value: unsupported.first) if unsupported.any?

    frequency = @parts["FREQ"]
    return problem(:invalid) if frequency.nil?
    return problem(:unsupported_frequency, value: frequency) unless FREQUENCIES.include?(frequency)

    check_numbers
    return unless valid?
    return problem(:invalid) unless values_readable?

    IceCube::Rule.from_ical(@rule)
  rescue StandardError
    problem(:invalid)
  end

  # Every part is KEY=VALUE, and no key repeats.
  def read_parts
    @rule.split(";").all? do |part|
      key, value, extra = part.split("=", -1)
      next false if key.blank? || value.blank? || extra || @parts.key?(key)

      @parts[key] = value
    end
  end

  def check_numbers
    { "INTERVAL" => MAX_INTERVAL, "COUNT" => MAX_COUNT }.each do |part, maximum|
      value = @parts[part]
      next if value.nil?

      if !value.match?(NUMBER)
        return problem(:invalid)
      elsif !value.to_i.between?(1, maximum)
        return problem(:out_of_range, part: part, minimum: 1, maximum: maximum)
      end
    end
  end

  def values_readable?
    return false if @parts.key?("COUNT") && @parts.key?("UNTIL")
    return false if @parts.key?("UNTIL") && !@parts["UNTIL"].match?(UTC_UNTIL)
    return false if @parts.key?("WKST") && !WEEKDAYS.include?(@parts["WKST"])

    return false if @parts["FREQ"] == "YEARLY" && !@parts.key?("BYMONTH") && (@parts.key?("BYDAY") || @parts.key?("BYMONTHDAY"))

    by_day_readable? && list_readable?("BYMONTHDAY", MONTH_DAY) { |day| day.abs.between?(1, 31) } &&
      list_readable?("BYMONTH", NUMBER) { |month| month.between?(1, 12) }
  end

  def by_day_readable?
    return true unless @parts.key?("BYDAY")

    numbered_allowed = @parts["FREQ"] == "MONTHLY" || (@parts["FREQ"] == "YEARLY" && @parts.key?("BYMONTH"))
    @parts["BYDAY"].split(",", -1).all? do |item|
      match = BYDAY_ITEM.match(item)
      match && (match[1].nil? || numbered_allowed)
    end
  end

  def list_readable?(part, format)
    return true unless @parts.key?(part)

    @parts[part].split(",", -1).all? { |item| item.match?(format) && yield(item.to_i) }
  end

  def problem(type, **options)
    @problems << Problem.new(type: type, options: options)
  end
end
