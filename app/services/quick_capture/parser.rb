class QuickCapture
  # Turns quick-capture text into what it asks for, without touching the
  # database. Rules, in order:
  #
  # 1. Money needs an explicit leading sign: "-250 kahve" is an expense,
  #    "+1.250,50 maaş" income. "3 yumurta al" is not money. An optional ₺/TL
  #    after the number is dropped from the description.
  # 2. "habit: koşu" or "alışkanlık: koşu" logs a habit.
  # 3. Text naming a day (yarın/tomorrow or a weekday, Turkish or English,
  #    with or without Turkish letters) is an event to confirm, not a record.
  #    Suffixed day words ("pazara", "Cuma'ya kadar") do not count, and a
  #    bare "pazar" (also "market") needs a lead-in, "günü" or a time. A time
  #    ("15:00", "15.30", "saat 9", "9'da", "3pm") is picked up when present.
  # 4. Anything else is a todo.
  class Parser
    # What the text asks for. Not named Money, Habit, Event or Todo: inside
    # the parser those names would hide the money gem and the models.
    MoneyEntry = Data.define(:kind, :amount, :description) # amount nil: unreadable number
    HabitEntry = Data.define(:name)
    EventHint = Data.define(:title, :date, :time, :keyword)
    TodoEntry = Data.define(:title)

    MONEY = /\A(?<sign>[+\-−–])(?<space>\s*)(?<prefix>₺\s*)?(?<number>\d(?:[\d.,]*\d)?)(?<rest>.*)\z/m
    # Another group of digits after the number: a phone number
    # ("+90 532 123 45 67 ara", "+90 (532) ..."), not an amount.
    DIGIT_GROUP = /\A\s+(?:\d|\(\d+\))/
    # "TRY" only in capitals: "-5 try the new place" keeps its "try".
    CURRENCY_MARKER = /\A\s*(?:₺|(?i:tl)(?![[:alpha:]])|TRY(?![[:alpha:]]))/
    HABIT = /\A(?:habit|al[ıi][şs]kanl[ıi]k)\s*:\s*(?<name>.*)\z/im

    # Longer words first so "cumartesi" is never read as "cuma".
    #
    # Alternations, not character classes: under /i Onigmo does not fold a
    # Latin-1 letter in a class that also holds an ASCII letter, so /[çc]/i
    # misses the "Ç" of an auto-capitalized "Çarşamba". "İ" is listed because
    # it does not fold to "i" ("PAZARTESİ").
    DAYS = {
      tomorrow: "yar(?:ı|i)n|tomorrow",
      1 => "pazartes(?:i|İ)|monday",
      2 => "sal(?:ı|i)|tuesday",
      3 => "(?:ç|c)ar(?:ş|s)amba|wednesday",
      4 => "per(?:ş|s)embe|thursday",
      6 => "cumartes(?:i|İ)|saturday",
      5 => "cuma|friday",
      0 => "pazar|sunday"
    }.freeze
    DAY_PATTERNS = DAYS.transform_values { |words| /\A(?:#{words})\z/i }.freeze
    # Whole words only ("masalı" is not "salı"), with an optional lead-in
    # ("next friday", "bu salı") and trailing "günü", all removed from the
    # title. A day word followed by letters, directly or after an apostrophe,
    # is a suffixed form ("pazara", "Cuma'ya kadar"): a deadline or a noun,
    # not the day of an event.
    DAY = /(?<![[:alpha:]])(?:(?<lead>next|this|on|bu|gelecek|önümüzdek(?:i|İ))\s+)?(?<day>#{DAYS.values.join("|")})(?:\s+(?<gunu>g(?:ü|u)n(?:ü|u)))?(?![[:alpha:]]|['’][[:alpha:]])/i
    # "pazar" also means "market" ("pazar alışverişi"); see #ambiguous_day?.
    AMBIGUOUS_DAY = /\Apazar\z/i

    TIME_PREFIX = /(?:(?<![[:alpha:]])(?:saat|at)\s+|@\s*)?/i
    # "'da", "'te", "'den" after a time, as in "saat 9'da".
    TIME_SUFFIX = /(?:['’]?[dt][ae]n?)?(?![[:alpha:]])/i
    TIME_AMPM = /#{TIME_PREFIX}(?<![\d:.])(?<hour>1[0-2]|0?[1-9])(?:[:.](?<min>[0-5]\d))?\s*(?<meridiem>[ap])\.?m\.?(?![[:alpha:]])/i
    # "12.50 TL" is a price, not ten to one.
    TIME_24H = /#{TIME_PREFIX}(?<![\d:.])(?<hour>[01]?\d|2[0-3])[:.](?<min>[0-5]\d)(?![\d:.])(?!\s*(?:₺|tl(?![[:alpha:]])))#{TIME_SUFFIX}/i
    TIME_SAAT = /(?<![[:alpha:]])saat\s*(?<hour>[01]?\d|2[0-3])(?![\d:.])#{TIME_SUFFIX}/i
    # A bare hour with a case suffix after an apostrophe: "9'da", "15'te",
    # "10’dan". Read as 24-hour, like "saat 9".
    TIME_HOUR_SUFFIX = /(?<![[:alnum:]:.,])(?<hour>[01]?\d|2[0-3])['’][dt][ae]n?(?![[:alpha:]])/i

    EDGE_PUNCTUATION = /\A[\s,;:.\-–—'’]+|[\s,;:\-–—]+\z/

    def self.parse(text, today:)
      new(text, today: today).parse
    end

    def initialize(text, today:)
      @text = text.to_s.strip
      @today = today
    end

    def parse
      money || habit || event || TodoEntry.new(title: @text)
    end

    private

    def money
      match = MONEY.match(@text)
      return unless match && amount_shaped?(match)

      description = match[:rest].sub(CURRENCY_MARKER, "").gsub(EDGE_PUNCTUATION, "")
      MoneyEntry.new(
        kind: match[:sign] == "+" ? "income" : "expense",
        amount: Amount.parse(match[:number]),
        description: description
      )
    end

    # Not a phone number, and not a list item: after a plain "-" with a
    # space ("- 3 yumurta al") the number must be marked as money, by a
    # currency after it ("- 250 TL kahve") or a ₺ before it ("- ₺250").
    def amount_shaped?(match)
      return false if DIGIT_GROUP.match?(match[:rest])
      return true unless match[:sign] == "-" && !match[:space].empty? && match[:prefix].nil?

      CURRENCY_MARKER.match?(match[:rest])
    end

    def habit
      match = HABIT.match(@text)
      HabitEntry.new(name: match[:name].strip) if match
    end

    # The first day word that is not ambiguous wins ("pazar alışverişi yarın"
    # is tomorrow); a lone ambiguous one counts only when a time is given.
    def event
      days = @text.to_enum(:scan, DAY).map { Regexp.last_match }
      day = days.find { |match| !ambiguous_day?(match) } || days.first
      return unless day

      rest = cut(@text, day)
      time, rest = extract_time(rest)
      return if time.nil? && ambiguous_day?(day)

      title = rest.squish.gsub(EDGE_PUNCTUATION, "")
      EventHint.new(title: title.presence || @text, date: date_for(day[:day]), time: time, keyword: day[:day])
    end

    # A bare "pazar" is Sunday only next to a lead-in ("bu pazar"), "günü"
    # ("pazar günü") or a time ("pazar 10:00"); otherwise it is the market.
    def ambiguous_day?(day)
      day[:lead].nil? && day[:gunu].nil? && AMBIGUOUS_DAY.match?(day[:day])
    end

    def date_for(word)
      key = DAY_PATTERNS.find { |_, pattern| pattern.match?(word) }.first
      return @today + 1 if key == :tomorrow

      # The next such weekday after today; on a Friday "cuma" is a week away.
      days_ahead = (key - @today.wday) % 7
      @today + (days_ahead.zero? ? 7 : days_ahead)
    end

    # Returns ["HH:MM" or nil, text without the time].
    def extract_time(text)
      if (match = TIME_AMPM.match(text))
        hour = match[:hour].to_i % 12 + (match[:meridiem].casecmp?("p") ? 12 : 0)
        [ format("%02d:%02d", hour, match[:min].to_i), cut(text, match) ]
      elsif (match = TIME_24H.match(text) || TIME_SAAT.match(text) || TIME_HOUR_SUFFIX.match(text))
        minutes = match.names.include?("min") ? match[:min].to_i : 0
        [ format("%02d:%02d", match[:hour].to_i, minutes), cut(text, match) ]
      else
        [ nil, text ]
      end
    end

    def cut(text, match)
      "#{text[0...match.begin(0)]} #{text[match.end(0)..]}"
    end
  end
end
