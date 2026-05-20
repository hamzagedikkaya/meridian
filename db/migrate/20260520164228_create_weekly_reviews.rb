class CreateWeeklyReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :weekly_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.date :week_starting, null: false
      t.datetime :completed_at
      t.text :reflection_went_well
      t.text :reflection_learned
      t.text :reflection_next_week

      t.timestamps
    end

    add_index :weekly_reviews, [ :user_id, :week_starting ], unique: true
  end
end
