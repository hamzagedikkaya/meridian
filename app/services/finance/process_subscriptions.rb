module Finance
  # Walks all active subscriptions, materializing any due charges as transactions
  # and advancing next_charge_on. Idempotent — only creates transactions for
  # subscriptions whose next_charge_on <= today.
  class ProcessSubscriptions
    def self.call(scope: Subscription.active, today: Date.current)
      created = 0

      scope.where(next_charge_on: ..today).includes(:user, :account, :finance_category).find_each do |sub|
        while sub.next_charge_on && sub.next_charge_on <= today
          ::Transaction.create!(
            user: sub.user,
            account: sub.account,
            finance_category: sub.finance_category,
            amount_cents: sub.amount_cents,
            kind: "expense",
            description: sub.name,
            note: "Auto-generated from subscription ##{sub.id}",
            date: sub.next_charge_on,
            occurred_at: sub.next_charge_on.to_time,
            recurring: true
          )
          sub.advance_next_charge! # eager_eye:disable LoopAssociation,CustomMethodQuery -- per-record save! is intentional
          created += 1
        end
      end

      created
    end
  end
end
