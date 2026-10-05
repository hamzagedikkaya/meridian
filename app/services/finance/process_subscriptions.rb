module Finance
  # Walks all active subscriptions, materializing any due charges as transactions
  # and advancing next_charge_on. Idempotent — only creates transactions for
  # subscriptions whose next_charge_on <= today.
  class ProcessSubscriptions
    def self.call(scope: Subscription.active, today: Date.current)
      created = 0

      scope.where(next_charge_on: ..today).includes(:user, :account, :finance_category).find_each do |sub|
        while sub.next_charge_on && sub.next_charge_on <= today
          charge!(sub) # eager_eye:disable LoopAssociation,CustomMethodQuery
          created += 1
        end
      end

      created
    end

    # Records one charge of +sub+: an expense on its account and category,
    # dated +date+ (the due date unless given), then next_charge_on moves one
    # period on. Both are saved or neither. Also used for a payment recorded
    # by hand (POST /api/v1/subscriptions/:id/charge).
    def self.charge!(sub, date: sub.next_charge_on)
      ApplicationRecord.transaction do
        transaction = ::Transaction.create!(
          user: sub.user,
          account: sub.account,
          finance_category: sub.finance_category,
          amount_cents: sub.amount_cents,
          kind: "expense",
          description: sub.name,
          date: date,
          occurred_at: date.to_time,
          recurring: true
        )
        sub.advance_next_charge!
        transaction
      end
    end
  end
end
