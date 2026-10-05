require "rails_helper"

RSpec.describe QuickCapture do
  let(:user) { create(:user) }

  def capture(text, **options)
    described_class.call(user, text, **options)
  end

  it "reports blank text as empty" do
    expect(capture("   ").type).to eq(:empty)
  end

  describe "money" do
    it "records an uncategorized transaction on the oldest active account, dated today" do
      create(:account, user: user, archived_at: Time.current)
      wallet = create(:account, user: user, name: "Cüzdan")
      create(:account, user: user, name: "Banka")

      result = capture("-1.250,50 market")

      expect(result.type).to eq(:transaction)
      expect(result.record).to have_attributes(
        account_id: wallet.id, kind: "expense", amount_cents: 125_050,
        description: "market", date: Date.current, finance_category_id: nil
      )
    end

    it "scales by the account currency's subunit" do
      create(:account, user: user, currency: "GAU")

      expect(capture("+5 altın").record).to have_attributes(kind: "income", amount_cents: 5)
    end

    it "refuses fractions of the smallest unit instead of rounding them" do
      create(:account, user: user, currency: "GAU")

      result = capture("-1,5 altın")

      expect(result).to have_attributes(type: :invalid_amount, reason: :too_precise, currency: "GAU")
      expect(result.amount_error_message).to eq("GAU amounts can't have that many decimal places.")
      expect(user.transactions).to be_empty
    end

    it "refuses zero and amounts the 4-byte column cannot hold" do
      create(:account, user: user)

      expect(capture("-0 kahve")).to have_attributes(type: :invalid_amount, reason: :zero)
      expect(capture("-21.474.836,48 x")).to have_attributes(type: :invalid_amount, reason: :too_large)
      expect(capture("-21.474.836,47 x").record.amount_cents).to eq(2_147_483_647)
    end

    it "reports an unreadable number" do
      create(:account, user: user)

      expect(capture("-1.25.0 market")).to have_attributes(type: :invalid_amount, reason: :unreadable)
    end

    it "reports no_account when the user has no active account" do
      create(:account, user: user, archived_at: Time.current)

      expect(capture("-250 kahve").type).to eq(:no_account)
    end

    it "describes an amount-only capture in the user's language" do
      create(:account, user: user)

      expect(capture("-250").record.description).to eq("Quick capture")
      expect(I18n.with_locale(:tr) { capture("-250") }.record.description).to eq("Hızlı ekleme")
    end
  end

  describe "habits" do
    it "completes a single-count daily habit, and a repeat keeps it completed" do
      habit = create(:habit, user: user, name: "Koşu", target_count: 1)

      2.times { capture("habit: koşu") }

      expect(habit.habit_logs.sole).to have_attributes(date: Date.current, count: 1, completed: true)
    end

    it "moves a multi-count daily habit one step per capture, up to its target" do
      habit = create(:habit, user: user, name: "Su", target_count: 3)

      expect(capture("habit: su").record).to have_attributes(count: 1, completed: false)
      2.times { capture("alışkanlık: su") }
      expect(capture("habit: su").record).to have_attributes(count: 3, completed: true)
      expect(habit.habit_logs.count).to eq(1)
    end

    it "marks today done for a weekly habit" do
      create(:habit, user: user, name: "Yüzme", frequency: "weekly", target_count: 3)

      expect(capture("habit: yüzme").record).to have_attributes(count: 3, completed: true)
    end

    it "matches names ignoring case, Turkish letters and accents" do
      kosu = create(:habit, user: user, name: "Koşu")
      english = create(:habit, user: user, name: "İngilizce")

      expect(capture("habit: KOŞU").record.habit_id).to eq(kosu.id)
      expect(capture("habit: kosu").record.habit_id).to eq(kosu.id)
      expect(capture("habit: ingilizce")).to have_attributes(type: :habit_log, name: "İngilizce")
      expect(english.habit_logs.count).to eq(1)
    end

    it "refuses a folded match that fits more than one habit" do
      create(:habit, user: user, name: "Koşu")
      create(:habit, user: user, name: "Koşü")

      expect(capture("habit: kosu")).to have_attributes(type: :unknown_habit, name: "kosu")
    end

    it "ignores archived habits and other users' habits" do
      create(:habit, user: user, name: "Okuma", archived_at: Time.current)
      create(:habit, name: "Yoga")

      expect(capture("habit: okuma")).to have_attributes(type: :unknown_habit, name: "okuma")
      expect(capture("habit: yoga").type).to eq(:unknown_habit)
      expect(HabitLog.count).to eq(0)
    end

    it "reports a bare prefix as empty" do
      expect(capture("habit:").type).to eq(:empty)
    end
  end

  describe "event suggestions" do
    it "returns the parsed suggestion and saves nothing" do
      result = capture("yarın 15:00 dişçi")

      expect(result).to have_attributes(type: :event_suggestion, record: nil)
      expect(result.suggestion).to have_attributes(title: "dişçi", date: Date.current + 1, time: "15:00")
      expect([ Event.count, Todo.count ]).to eq([ 0, 0 ])
    end
  end

  describe "todos" do
    it "saves plain text as a pending, medium-priority todo" do
      result = capture("süt al")

      expect(result.type).to eq(:todo)
      expect(result.record).to have_attributes(user_id: user.id, title: "süt al", priority: "medium", status: "pending")
    end

    it "saves the text verbatim when as: :todo, skipping every other rule" do
      create(:account, user: user)

      expect(capture("yarın dişçi", as: "todo").record).to have_attributes(title: "yarın dişçi")
      expect(capture("-250 kahve", as: :todo).record).to have_attributes(title: "-250 kahve")
      expect(user.transactions).to be_empty
    end

    it "returns the invalid record instead of raising when the todo cannot be saved" do
      result = capture("x" * 201)

      expect(result.type).to eq(:invalid)
      expect(result.record.errors).to include(:title)
    end
  end
end
