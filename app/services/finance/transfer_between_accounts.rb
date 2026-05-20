module Finance
  class TransferBetweenAccounts
    Result = Struct.new(:success?, :transaction, :error, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(user:, from_account:, to_account:, amount_cents:, date: Date.current, description: nil, note: nil)
      @user = user
      @from_account = from_account
      @to_account = to_account
      @amount_cents = amount_cents
      @date = date
      @description = description
      @note = note
    end

    def call
      return Result.new(success?: false, error: "Cannot transfer to the same account") if @from_account == @to_account
      return Result.new(success?: false, error: "Amount must be positive") unless @amount_cents.to_i.positive?

      transaction = nil
      ::Transaction.transaction do
        transaction = ::Transaction.create!(
          user: @user,
          account: @from_account,
          related_account: @to_account,
          amount_cents: @amount_cents,
          kind: "transfer",
          description: @description || "Transfer to #{@to_account.name}",
          note: @note,
          date: @date,
          occurred_at: Time.current
        )
      end

      Result.new(success?: true, transaction: transaction)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
