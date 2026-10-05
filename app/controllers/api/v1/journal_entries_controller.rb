module Api
  module V1
    class JournalEntriesController < BaseController
      RANGES = ::JournalEntriesController::RANGES
      DEFAULT_RANGE = ::JournalEntriesController::DEFAULT_RANGE

      # The stored body has formatting from the web that a plain-text body
      # would drop, and the client did not confirm dropping it.
      class BodyHasFormatting < StandardError
        attr_reader :formatting

        def initialize(formatting)
          @formatting = formatting
          super("body has formatting: #{formatting.join(", ")}")
        end
      end

      before_action :set_entry, only: [ :show, :update, :destroy ]

      rescue_from BodyHasFormatting, with: :render_body_has_formatting

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
            journal_streak_weeks: JournalEntry.current_week_streak_for(current_user),
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
        # A missing (or null) date is the user's today, as the web form
        # defaults. A date that was sent but cannot be read ("2026-02-30")
        # casts to nil and still fails validation, as it does on the web.
        entry.date = Date.current if params[:date].nil?
        assign_body(entry)
        if entry.save
          render json: { entry: Serialize.journal_entry(entry, full: true) }, status: :created
        else
          render_errors(entry)
        end
      end

      # Only the keys sent change. Every parameter is checked before anything
      # is saved.
      def update
        discard_formatting = boolean_param(:discard_formatting)
        @entry.assign_attributes(entry_params)
        assign_body(@entry, discard_formatting: discard_formatting)
        if @entry.save
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

      # body_text loses its control characters, NUL included
      # (JournalEntry::CONTROL_CHARACTERS), instead of being refused.
      def null_byte_cleaned_params
        %w[body_text]
      end

      def set_entry
        @entry = current_user.journal_entries.find(params[:id])
      end

      # The body comes separately (#assign_body).
      def entry_params
        params.permit(:date, :title, :mood, :weather, :energy_level, :gratitude, :tags)
      end

      # body_text is plain text, stored as paragraphs and line breaks
      # (JournalEntry#body_text=); body is HTML, stored as sent, as before.
      # A request sends one of them, or neither to leave the body alone.
      def assign_body(entry, discard_formatting: nil)
        if params.key?(:body_text)
          raise InvalidParameter, :body if params.key?(:body)

          assign_body_text(entry, string_param(:body_text), discard_formatting)
        elsif params.key?(:body)
          assign_body_html(entry, string_param(:body))
        end
      end

      # A body with formatting from the web (bold, lists, links, ...) is
      # replaced by plain text only when the client confirms it with
      # discard_formatting=true. The same text sent back unchanged keeps the
      # body as it is, formatting included, so editing the other fields of a
      # web entry on the phone loses nothing.
      def assign_body_text(entry, text, discard_formatting)
        formatting = entry.new_record? ? [] : entry.body_formatting
        if formatting.any?
          return if entry.same_body_text?(text)
          raise BodyHasFormatting, formatting unless discard_formatting
        end
        entry.body_text = text
      end

      # Older app versions fill their editor with the entry's text and send
      # it back as body on every save. When that text is unchanged the stored
      # body stays, so its formatting and paragraphs are not flattened.
      def assign_body_html(entry, html)
        return if entry.persisted? && entry.same_body_text?(html)

        entry.body = html
      end

      def render_body_has_formatting(exception)
        render_unprocessable(:body_has_formatting,
          field: :body_text,
          message: I18n.t("api.errors.body_has_formatting"),
          body_formatting: exception.formatting)
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
