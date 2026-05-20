class AddGoalToHabitsAndTodosAndSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_reference :habits,        :goal, foreign_key: true
    add_reference :todos,         :goal, foreign_key: true
    add_reference :subscriptions, :goal, foreign_key: true
  end
end
