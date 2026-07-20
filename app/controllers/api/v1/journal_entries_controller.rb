module Api
  module V1
    class JournalEntriesController < BaseController
      RANGES = ::JournalEntriesController::RANGES
      DEFAULT_RANGE = ::JournalEntriesController::DEFAULT_RANGE

      before_action :set_entry, only: [ :show, :update, :destroy ]

      def index
        range = RANGES.include?(params[:range]) ? params[:range] : DEFAULT_RANGE
        range_start = range_start_for(range)

        scope = current_user.journal_entries
        scope = scope.where(date: range_start..Date.current) if range_start
        entries = scope.recent.with_rich_text_body.limit(180)
        mood_data = scope.where.not(mood: nil).group(:mood).count

        render json: {
          entries: entries.map { |entry| Serialize.journal_entry(entry) },
          meta: {
            entries_count: scope.count,
            journal_streak: JournalEntry.current_streak_for(current_user),
            mood_counts: JournalEntry::MOODS.index_with { |mood| mood_data[mood] || 0 },
            range: range
          }
        }
      end

      def show
        render json: { entry: Serialize.journal_entry(@entry, full: true) }
      end

      def create
        entry = current_user.journal_entries.new(entry_params)
        if entry.save
          render json: { entry: Serialize.journal_entry(entry, full: true) }, status: :created
        else
          render_errors(entry)
        end
      end

      def update
        if @entry.update(entry_params)
          render json: { entry: Serialize.journal_entry(@entry, full: true) }
        else
          render_errors(@entry)
        end
      end

      def destroy
        @entry.destroy
        head :no_content
      end

      private

      def set_entry
        @entry = current_user.journal_entries.find(params[:id])
      end

      def entry_params
        params.permit(:date, :title, :body, :mood, :weather, :energy_level, :gratitude, :tags)
      end

      def range_start_for(range)
        case range
        when "1d"  then Date.current
        when "7d"  then 6.days.ago.to_date
        when "30d" then 29.days.ago.to_date
        when "6mo" then 6.months.ago.to_date
        when "1y"  then 1.year.ago.to_date
        end
      end
    end
  end
end
