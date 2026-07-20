module Api
  module V1
    class TodosController < BaseController
      def index
        scope = current_user.todos.includes(:todo_list, :subtasks)
        scope = case params[:filter]
        when "today"    then scope.due_today
        when "week"     then scope.due_this_week
        when "overdue"  then scope.overdue
        when "done"     then scope.done
        else                  scope.open
        end
        scope = scope.where(todo_list_id: params[:list_id]) if params[:list_id].present?
        scope = scope.where(priority: params[:priority])     if params[:priority].present?

        todos = scope.ordered.order(due_at: :asc, created_at: :desc)

        render json: {
          todos: todos.map { |todo| Serialize.todo(todo) },
          meta: {
            open_count: current_user.todos.open.count,
            overdue_count: current_user.todos.overdue.count
          }
        }
      end

      def create
        todo = current_user.todos.new(todo_params)
        if todo.save
          render json: { todo: Serialize.todo(todo) }, status: :created
        else
          render_errors(todo)
        end
      end

      def update
        todo = current_user.todos.find(params[:id])
        if todo.update(todo_params)
          render json: { todo: Serialize.todo(todo) }
        else
          render_errors(todo)
        end
      end

      def toggle
        todo = current_user.todos.find(params[:id])
        todo.update(status: todo.done? ? "pending" : "done")
        render json: { id: todo.id, status: todo.status, completed_at: todo.completed_at }
      end

      private

      def todo_params
        permitted = params.permit(:title, :body, :priority, :due_at, :todo_list_id, :goal_id)
        permitted[:todo_list_id] = current_user.todo_lists.find(permitted[:todo_list_id]).id if permitted[:todo_list_id].present?
        permitted[:goal_id] = current_user.goals.find(permitted[:goal_id]).id if permitted[:goal_id].present?
        permitted
      end
    end
  end
end
