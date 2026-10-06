module Api
  module V1
    class TodoListsController < BaseController
      DELETE_MODES = %w[delete keep].freeze

      before_action :set_list, only: [ :show, :update, :destroy ]

      # Active lists in the web's order (position, then name), as the web's
      # todo pickers show them. include_archived=true appends the archived
      # ones in the same order, like the web's lists page.
      def index
        lists = current_user.todo_lists.active.ordered.order(:id).to_a
        lists += current_user.todo_lists.archived.ordered.order(:id).to_a if boolean_param(:include_archived)
        counts = todo_counts([ *lists.map(&:id), nil ])

        render json: {
          todo_lists: lists.map { |list| list_json(list, counts) },
          meta: { unlisted_open_count: counts.dig(nil, :open) || 0 }
        }
      end

      def show
        render json: { todo_list: list_json(@list) }
      end

      # The web form's fields (TodoListsController#list_params), flat. A new
      # list is always active.
      def create
        list = current_user.todo_lists.new(list_attributes)
        if save_checked(list) { check_color(list) }
          render json: { todo_list: list_json(list) }, status: :created
        else
          render_errors(list)
        end
      end

      # Only the keys sent change. archived=true|false archives or restores
      # the list (the web form sets archived_at itself); archiving an
      # archived list keeps its first archived_at. Its todos are untouched.
      def update
        @list.assign_attributes(list_attributes)
        archived = required_boolean_param(:archived) if params.key?(:archived)
        @list.archived_at = archived ? (@list.archived_at || Time.current) : nil unless archived.nil?

        if save_checked(@list) { check_color(@list) }
          render json: { todo_list: list_json(@list) }
        else
          render_errors(@list)
        end
      end

      # todos=delete (the default) deletes the list's todos with it.
      # todos=keep moves them out of the list first, so they stay as todos
      # without a list (what the web's delete does). Either way in one
      # transaction.
      def destroy
        keep = choice_param(:todos, DELETE_MODES, default: "delete") == "keep"
        TodoList.transaction do
          keep ? @list.todos.update_all(todo_list_id: nil, updated_at: Time.current) : delete_todos(@list)
          @list.destroy!
        end
        head :no_content
      end

      private

      def set_list
        @list = current_user.todo_lists.find(params[:id])
      end

      def list_attributes
        attrs = params.permit(:name, :color).to_h
        attrs[:position] = required_integer_param(:position) if params.key?(:position)
        attrs
      end

      # What destroying each todo did (Todo's dependents), in a few statements
      # instead of three per todo: their focus sessions stay in the history
      # unlinked, subtasks outside the list lose their parent, and the todos
      # go (a subtask inside the list goes in the same DELETE as its parent).
      def delete_todos(list)
        ids = list.todos.ids
        return if ids.empty?

        FocusSession.where(todo_id: ids).update_all(todo_id: nil)
        Todo.where(parent_id: ids).where.not(id: ids).update_all(parent_id: nil, updated_at: Time.current)
        Todo.where(id: ids).delete_all
      end

      def list_json(list, counts = todo_counts([ list.id ]))
        Serialize.todo_list(list,
          open_count: counts.dig(list.id, :open) || 0,
          todos_count: counts.dig(list.id, :total) || 0)
      end

      # { list_id => { open:, total: } } for the given list ids (nil: the
      # todos in no list), in one query.
      def todo_counts(list_ids)
        rows = current_user.todos.where(todo_list_id: list_ids).group(:todo_list_id, :status).count
        rows.each_with_object({}) do |((list_id, status), count), counts|
          entry = counts[list_id] ||= { open: 0, total: 0 }
          entry[:total] += count
          entry[:open] += count if Todo::OPEN_STATUSES.include?(status)
        end
      end
    end
  end
end
