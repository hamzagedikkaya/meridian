class QuickCapture
  # Reads the number of a money capture, written Turkish or English style:
  #
  #   250 · 12,50 · 12.50 · 1250,5 · 1.250 · 1,250 · 1.250,50 · 1,250.50 · 1.000.000
  #
  # When both separators appear, the last one is the decimal point and the
  # other groups thousands. A separator that appears more than once groups
  # thousands. A single separator followed by exactly three digits after a
  # 1-3 digit lead ("1.250", "12,500") groups thousands too, because nobody
  # writes 1.25 as "1.250"; any other single separator is the decimal point.
  #
  # Returns a BigDecimal, or nil when the grouping is inconsistent
  # ("1.25.0", "1,25.5", "1.250,5.5").
  module Amount
    NUMBER = /\A\d+(?:[.,]\d+)*\z/
    LEADING_GROUP = /\A[1-9]\d{0,2}\z/
    GROUP = /\A\d{3}\z/

    module_function

    def parse(number)
      number = number.to_s
      return nil unless number.match?(NUMBER)

      normalized =
        case number.scan(/[.,]/).uniq.size
        when 0 then number
        when 1 then single_separator(number)
        else        mixed_separators(number)
        end
      normalized && BigDecimal(normalized)
    end

    def single_separator(number)
      parts = number.split(/[.,]/)
      return parts.join if grouped?(parts)

      parts.size == 2 ? parts.join(".") : nil
    end

    def mixed_separators(number)
      decimal = number[number.rindex(/[.,]/)]
      return nil unless number.count(decimal) == 1

      integer, fraction = number.split(decimal)
      thousands = decimal == "." ? "," : "."
      return nil unless grouped?(integer.split(thousands))

      "#{integer.delete(thousands)}.#{fraction}"
    end

    def grouped?(parts)
      parts.first.match?(LEADING_GROUP) && parts.drop(1).all? { |part| part.match?(GROUP) }
    end
  end
end
