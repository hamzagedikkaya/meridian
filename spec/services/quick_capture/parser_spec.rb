require "rails_helper"

RSpec.describe QuickCapture::Parser do
  let(:today) { Date.new(2026, 10, 7) } # a Wednesday

  def parse(text)
    described_class.parse(text, today: today)
  end

  def money(kind, amount, description)
    described_class::MoneyEntry.new(kind: kind, amount: amount && BigDecimal(amount), description: description)
  end

  def todo(title)
    described_class::TodoEntry.new(title: title)
  end

  describe "money" do
    it "reads a leading minus as an expense and the rest as the description" do
      expect(parse("-250 kahve")).to eq(money("expense", "250", "kahve"))
    end

    it "reads a leading plus as income" do
      expect(parse("+1000 maaş")).to eq(money("income", "1000", "maaş"))
    end

    {
      "-12,50 simit" => "12.50",
      "-12.5 simit" => "12.5",
      "-1.250 simit" => "1250",
      "-1,250 simit" => "1250",
      "-1.250,50 simit" => "1250.50",
      "-1,250.50 simit" => "1250.50",
      "-1250,5 simit" => "1250.5"
    }.each do |text, amount|
      it "reads #{text.inspect} as #{amount}" do
        expect(parse(text)).to eq(money("expense", amount, "simit"))
      end
    end

    it "accepts a Unicode minus, an en dash and spaces after the sign" do
      expect(parse("− 250 kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("–250 kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("+ 1.000 prim")).to eq(money("income", "1000", "prim"))
    end

    it "drops a ₺, TL or TRY marker after the number" do
      expect(parse("-250 TL kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("-250tl kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("-12,50₺ simit")).to eq(money("expense", "12.50", "simit"))
      expect(parse("-80 TRY taksi")).to eq(money("expense", "80", "taksi"))
    end

    it "keeps a lowercase 'try' and words that only start with tl" do
      expect(parse("-5 try the new place")).to eq(money("expense", "5", "try the new place"))
      expect(parse("-5 tlf kartı")).to eq(money("expense", "5", "tlf kartı"))
    end

    it "strips punctuation between the amount and the description" do
      expect(parse("-250, kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("-250: kahve")).to eq(money("expense", "250", "kahve"))
    end

    it "leaves the description empty when only an amount is given" do
      expect(parse("-250")).to eq(money("expense", "250", ""))
    end

    it "flags an unreadable number instead of guessing" do
      expect(parse("-1.25.0 market")).to eq(money("expense", nil, "market"))
    end

    it "does not read text that merely starts with a number as money" do
      expect(parse("3 yumurta al")).to eq(todo("3 yumurta al"))
      expect(parse("250 kahve")).to eq(todo("250 kahve"))
    end

    it "does not read a phone number as money" do
      expect(parse("+90 532 123 45 67 ara")).to eq(todo("+90 532 123 45 67 ara"))
      expect(parse("+90 (532) 123 4567")).to eq(todo("+90 (532) 123 4567"))
    end

    it "does not read a list item as money, unless a currency marks the number" do
      expect(parse("- 3 yumurta al")).to eq(todo("- 3 yumurta al"))
      expect(parse("- 250 TL kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("- ₺250 kahve")).to eq(money("expense", "250", "kahve"))
    end

    it "reads a ₺ before the number" do
      expect(parse("-₺250 kahve")).to eq(money("expense", "250", "kahve"))
      expect(parse("+₺ 1.000 prim")).to eq(money("income", "1000", "prim"))
    end

    it "still reads a number followed by words or a bracket as money" do
      expect(parse("-250 (2 kişi) yemek")).to eq(money("expense", "250", "(2 kişi) yemek"))
    end

    it "does not read a sign without a digit as money" do
      expect(parse("- süt al")).to eq(todo("- süt al"))
    end
  end

  describe "habits" do
    [ "habit: koşu", "Habit:koşu", "HABIT : koşu", "alışkanlık: koşu", "ALIŞKANLIK: koşu", "aliskanlik: koşu" ].each do |text|
      it "reads #{text.inspect} as a habit log" do
        expect(parse(text)).to eq(described_class::HabitEntry.new(name: "koşu"))
      end
    end

    it "returns a blank name for a bare prefix" do
      expect(parse("habit:   ")).to eq(described_class::HabitEntry.new(name: ""))
    end

    it "only reads the prefix at the start" do
      expect(parse("yeni habit: koşu")).to eq(todo("yeni habit: koşu"))
    end
  end

  describe "event suggestions" do
    it "reads yarın as tomorrow and removes it from the title" do
      expect(parse("yarın dişçi")).to eq(
        described_class::EventHint.new(title: "dişçi", date: Date.new(2026, 10, 8), time: nil, keyword: "yarın")
      )
    end

    it "finds the day word anywhere, in any case, with or without Turkish letters" do
      expect(parse("Lunch with Ahmet tomorrow")).to have_attributes(title: "Lunch with Ahmet", date: Date.new(2026, 10, 8))
      expect(parse("YARIN DİŞÇİ")).to have_attributes(title: "DİŞÇİ", date: Date.new(2026, 10, 8))
      expect(parse("yarin disci")).to have_attributes(title: "disci", date: Date.new(2026, 10, 8))
    end

    {
      "pazartesi" => Date.new(2026, 10, 12), "salı" => Date.new(2026, 10, 13), "sali" => Date.new(2026, 10, 13),
      "SALI" => Date.new(2026, 10, 13), "perşembe" => Date.new(2026, 10, 8), "persembe" => Date.new(2026, 10, 8),
      "cuma" => Date.new(2026, 10, 9), "cumartesi" => Date.new(2026, 10, 10),
      "monday" => Date.new(2026, 10, 12), "Friday" => Date.new(2026, 10, 9), "sunday" => Date.new(2026, 10, 11)
    }.each do |word, date|
      it "reads #{word.inspect} as the next such day, #{date}" do
        expect(parse("#{word} toplantı")).to have_attributes(title: "toplantı", date: date)
      end
    end

    # Phone keyboards capitalize the first letter: "Çarşamba", not "çarşamba".
    {
      "Çarşamba" => Date.new(2026, 10, 14), "ÇARŞAMBA" => Date.new(2026, 10, 14), "Perşembe" => Date.new(2026, 10, 8),
      "PAZARTESİ" => Date.new(2026, 10, 12), "CUMARTESİ" => Date.new(2026, 10, 10), "YARIN" => Date.new(2026, 10, 8)
    }.each do |word, date|
      it "reads the capitalized #{word.inspect} as #{date}" do
        expect(parse("#{word} toplantı")).to have_attributes(title: "toplantı", date: date, keyword: word)
      end
    end

    it "puts today's weekday a week away" do
      expect(parse("çarşamba yoga").date).to eq(Date.new(2026, 10, 14))
      expect(parse("wednesday yoga").date).to eq(Date.new(2026, 10, 14))
    end

    it "removes lead-ins and 'günü' around the day from the title, in any case" do
      expect(parse("bu salı günü dişçi").title).to eq("dişçi")
      expect(parse("next friday standup").title).to eq("standup")
      expect(parse("ÖNÜMÜZDEKİ CUMA sunum").title).to eq("sunum")
      expect(parse("Cuma Günü sunum").title).to eq("sunum")
    end

    describe "pazar, which is also 'market'" do
      it "is Sunday with a lead-in, 'günü' or a time" do
        sunday = Date.new(2026, 10, 11)
        expect(parse("bu pazar piknik")).to have_attributes(title: "piknik", date: sunday, time: nil)
        expect(parse("PAZAR GÜNÜ maç")).to have_attributes(title: "maç", date: sunday, time: nil)
        expect(parse("pazar 10:00 kahvaltı")).to have_attributes(title: "kahvaltı", date: sunday, time: "10:00")
        expect(parse("pazar 10'da kahvaltı")).to have_attributes(title: "kahvaltı", date: sunday, time: "10:00")
      end

      it "is a todo on its own" do
        expect(parse("pazar alışverişi")).to eq(todo("pazar alışverişi"))
        expect(parse("Pazar")).to eq(todo("Pazar"))
        expect(parse("pazar 12.50 TL")).to eq(todo("pazar 12.50 TL"))
      end

      it "gives way to another day word in the text" do
        expect(parse("pazar alışverişi yarın 10'da")).to have_attributes(
          title: "pazar alışverişi", date: Date.new(2026, 10, 8), time: "10:00", keyword: "yarın"
        )
      end
    end

    {
      "yarın 15:00 dişçi" => [ "15:00", "dişçi" ],
      "yarın 9.30 toplantı" => [ "09:30", "toplantı" ],
      "yarın saat 9'da dişçi" => [ "09:00", "dişçi" ],
      "yarın 9'da dişçi" => [ "09:00", "dişçi" ],
      "cuma 15’te toplantı" => [ "15:00", "toplantı" ],
      "yarın 10'dan itibaren nöbet" => [ "10:00", "itibaren nöbet" ],
      "cuma 19:30'da yemek" => [ "19:30", "yemek" ],
      "tomorrow at 3pm dentist" => [ "15:00", "dentist" ],
      "tomorrow 10:15 am standup" => [ "10:15", "standup" ],
      "tomorrow 12am deploy" => [ "00:00", "deploy" ]
    }.each do |text, (time, title)|
      it "reads the time in #{text.inspect}" do
        expect(parse(text)).to have_attributes(time: time, title: title)
      end
    end

    it "does not read a price as a time" do
      expect(parse("yarın 12.50 TL fatura")).to have_attributes(time: nil, title: "12.50 TL fatura")
    end

    it "does not read a suffixed number that is not an hour as a time" do
      expect(parse("yarın 24'te")).to have_attributes(time: nil, title: "24'te")
      expect(parse("yarın 1,5'te")).to have_attributes(time: nil, title: "1,5'te")
      expect(parse("yarın COVID19'da")).to have_attributes(time: nil, title: "COVID19'da")
    end

    it "keeps the whole text as the title when only the day is given" do
      expect(parse("yarın")).to have_attributes(title: "yarın", date: Date.new(2026, 10, 8))
    end

    it "only matches whole words" do
      expect(parse("masalı oku")).to eq(todo("masalı oku"))
      expect(parse("yarınki toplantıyı hazırla")).to eq(todo("yarınki toplantıyı hazırla"))
      expect(parse("pazara git")).to eq(todo("pazara git"))
      expect(parse("cumartesi maç").date).to eq(Date.new(2026, 10, 10))
    end

    it "treats a day word with a suffix after an apostrophe as suffixed" do
      expect(parse("Cuma'ya kadar rapor")).to eq(todo("Cuma'ya kadar rapor"))
      expect(parse("pazartesi’ye kadar bitir")).to eq(todo("pazartesi’ye kadar bitir"))
      expect(parse("'cuma' sunumu").date).to eq(Date.new(2026, 10, 9))
    end
  end

  describe "todos" do
    it "turns anything else into a todo with the trimmed text as the title" do
      expect(parse("  süt al  ")).to eq(todo("süt al"))
    end
  end
end
