module Api
  module V1
    class GoalsController < BaseController
      before_action :set_goal, only: [ :show, :update, :update_progress, :recalculate ]

      def index
        goals = current_user.goals.includes(:related).ordered.to_a
        goals.each { |goal| goal.recalculate_progress! if goal.status == "active" }
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

      def create
        goal = current_user.goals.new(goal_params)
        apply_related_param(goal)
        if goal.save
          render json: { goal: Serialize.goal(goal) }, status: :created
        else
          render_errors(goal)
        end
      end

      def update
        apply_related_param(@goal)
        if @goal.update(goal_params)
          render json: { goal: Serialize.goal(@goal) }
        else
          render_errors(@goal)
        end
      end

      def update_progress
        new_value = if params[:delta].present?
          @goal.current_value.to_f + params[:delta].to_f
        elsif params[:current_value].present?
          params[:current_value].to_f
        else
          @goal.current_value.to_f
        end

        new_value = [ new_value, 0 ].max
        status = new_value >= @goal.target_value.to_f ? "achieved" : "active"
        @goal.update!(current_value: new_value, status: @goal.status == "abandoned" ? "abandoned" : status)

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

      def apply_related_param(goal)
        raw = params[:related]
        return if raw.blank?
        if raw == "none"
          goal.related = nil
          return
        end
        type, id = raw.to_s.split("-", 2)
        return unless %w[Account Habit].include?(type) && id.present?

        record = type.constantize.where(user_id: current_user.id).find_by(id: id)
        goal.related = record if record
      end

      def goal_params
        params.permit(:name, :description, :target_type, :target_value, :current_value, :unit, :deadline, :color, :status)
      end
    end
  end
end
