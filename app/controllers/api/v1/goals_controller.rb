module Api
  module V1
    class GoalsController < BaseController
      # The composite the web's goal form sends: "Account-12", "Habit-7".
      RELATED = /\A(Account|Habit)-(\d+)\z/
      # What each target type links to. The web form offers accounts for a
      # financial goal, habits for a habit goal, and no link for a custom one
      # (goal_form_controller.js); a link of another kind would be ignored by
      # Goals::CalculateProgress.
      LINK_TYPES = { "financial" => "Account", "habit" => "Habit" }.freeze
      DECIMAL = /\A[+-]?\d+(\.\d+)?\z/
      # target_value and current_value are decimal(14, 2).
      VALUE_LIMIT = BigDecimal("1e12")

      before_action :set_goal, only: [ :show, :update, :destroy, :update_progress, :recalculate ]

      # Every goal is recomputed before it is listed, as GET /goals/:id
      # does. Only active goals used to be, so a goal whose value had dropped
      # below its target listed as achieved and opened as active.
      def index
        goals = current_user.goals.includes(:related, :user).ordered.to_a
        goals.each(&:recalculate_progress!)
        grouped = goals.group_by(&:status)
        render json: {
          active: (grouped["active"] || []).map { |goal| Serialize.goal(goal) },
          achieved: (grouped["achieved"] || []).map { |goal| Serialize.goal(goal) },
          abandoned: (grouped["abandoned"] || []).map { |goal| Serialize.goal(goal) }
        }
      end

      def show
        @goal.recalculate_progress!
        render json: { goal: Serialize.goal(@goal) }
      end

      # The unit defaults to the user's currency, as the web form prefills it.
      def create
        goal = current_user.goals.new(unit: current_user.currency)
        assign_goal(goal)
        save_goal(goal, :created)
      end

      # Only the keys sent change.
      def update
        assign_goal(@goal)
        save_goal(@goal, :ok)
      end

      # As on the web: its habits, todos and subscriptions stay, without a
      # goal (Goal has_many ..., dependent: :nullify).
      def destroy
        @goal.destroy!
        head :no_content
      end

      # Progress logged by hand: current_value, or delta added to it, never
      # below 0. Only for goals whose progress is manual; any other value is
      # recomputed on every read, so a logged one would not last.
      def update_progress
        delta = decimal_param(:delta)
        current = decimal_param(:current_value)
        progress = Goals::CalculateProgress.new(@goal)
        return render_progress_computed(progress.source) unless progress.source == "manual"

        value = if delta
          @goal.current_value + delta
        else
          current || @goal.current_value
        end
        value = [ value, 0 ].max
        check_limit!(value)
        @goal.update!(current_value: value, status: progress.status_for(value))

        render json: { goal: Serialize.goal(@goal) }
      end

      def recalculate
        @goal.recalculate_progress!
        render json: { goal: Serialize.goal(@goal) }
      end

      private

      def set_goal
        @goal = current_user.goals.find(params[:id])
      end

      # A change of target type drops a link that no longer fits it, as the
      # web form clears the other kind's option when the type changes, unless
      # the request sets the link itself. The progress is first brought up to
      # date from the link the goal has, so a goal that loses its link keeps
      # the value it had at that moment.
      def assign_goal(goal)
        type_before = goal.target_type
        goal.current_value = Goals::CalculateProgress.new(goal).value if goal.persisted?
        goal.assign_attributes(goal_attributes)
        if params.key?(:related)
          goal.related = related_param
        elsif goal.target_type != type_before && !link_fits?(goal)
          goal.related = nil
        end
      end

      # permit drops a list or an object silently; for status that would read
      # as "keep the current status" (#save_goal), so it is refused instead.
      def goal_attributes
        string_param(:status)

        attrs = params.permit(:name, :description, :target_type, :unit, :color, :status).to_h
        attrs[:target_value] = decimal_param(:target_value) if params.key?(:target_value)
        attrs[:current_value] = decimal_param(:current_value) if params.key?(:current_value)
        attrs[:deadline] = date_param(:deadline) if params.key?(:deadline)
        attrs
      end

      # "Account-<id>" or "Habit-<id>": one of the user's accounts or habits,
      # archived ones included (404 otherwise). "none", null or "" unlinks.
      def related_param
        raw = params[:related]
        return nil if raw.nil? || raw == "" || raw == "none"

        match = RELATED.match(raw) if raw.is_a?(String)
        raise InvalidParameter, :related unless match

        scope = match[1] == "Account" ? current_user.accounts : current_user.habits
        scope.find(match[2])
      end

      def link_fits?(goal)
        goal.related.nil? || goal.related.class.name == LINK_TYPES[goal.target_type]
      end

      # Validates, recomputes the progress the way every read does, settles
      # the status and saves, so the response is what the next GET returns.
      def save_goal(goal, http_status)
        requested = goal.status if params.key?(:status)
        goal.validate
        check_goal(goal)
        return render_errors(goal) if goal.errors.any?

        progress = Goals::CalculateProgress.new(goal)
        goal.current_value = progress.value
        conflict = status_conflict(goal, requested, progress)
        return render_status_conflict(conflict, goal, progress) if conflict

        goal.save!
        render json: { goal: Serialize.goal(goal) }, status: http_status
      end

      # A goal that is not abandoned is achieved exactly when its progress
      # reaches the target, and every read applies that rule
      # (Goals::CalculateProgress). Without a status the goal takes the one
      # its progress implies (abandoned stays abandoned). A status the
      # progress contradicts would flip back on the next read, so it is
      # refused rather than saved.
      def status_conflict(goal, requested, progress)
        implied = progress.status_for(goal.current_value)
        case requested
        when nil
          goal.status = implied
          nil
        when "active"   then :target_reached if implied == "achieved"
        when "achieved" then :target_not_reached if implied == "active"
        end
      end

      def render_status_conflict(code, goal, progress)
        render_unprocessable(code,
          field: :status,
          message: I18n.t(code, scope: "api.errors"),
          current_value: goal.current_value.to_f,
          target_value: goal.target_value.to_f,
          progress_source: progress.source)
      end

      def render_progress_computed(source)
        render_unprocessable(:progress_computed,
          field: :current_value,
          message: I18n.t("api.errors.progress_computed"),
          progress_source: source)
      end

      def check_goal(goal)
        check_color(goal)
        check_link(goal)
        check_current_value(goal)
      end

      # Checked when the link or the type changes, so a goal linked on the
      # web to a record of another kind stays editable.
      def check_link(goal)
        return unless goal.related_id_changed? || goal.related_type_changed? || goal.target_type_changed?

        goal.errors.add(:related, :must_match_target_type) unless link_fits?(goal)
      end

      # The column cannot be null, and the web form's field starts at 0. Only
      # a value the client sent is checked: a computed one can be negative
      # (an overdrawn account).
      def check_current_value(goal)
        return unless params.key?(:current_value)

        if goal.current_value.nil?
          goal.errors.add(:current_value, :not_a_number)
        elsif goal.current_value.negative?
          goal.errors.add(:current_value, :greater_than_or_equal_to, count: 0)
        end
      end

      # A number from a JSON number or a decimal string ("12.5"); nil when
      # absent or null. 422 invalid_parameter for anything else ("abc", "",
      # "12,5"); 422 value_out_of_range for 10^12 or more, which
      # decimal(14, 2) cannot hold.
      def decimal_param(name)
        value = params[name]
        return nil if value.nil?

        number = case value
        when Integer then BigDecimal(value)
        when Float   then BigDecimal(value.to_s)
        when String  then BigDecimal(value.strip) if value.strip.match?(DECIMAL)
        end
        raise InvalidParameter, name unless number

        check_limit!(number)
        number
      end

      def check_limit!(number)
        raise ActiveModel::RangeError, "#{number} does not fit decimal(14, 2)" if number.abs >= VALUE_LIMIT
      end
    end
  end
end
