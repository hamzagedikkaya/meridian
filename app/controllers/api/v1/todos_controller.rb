module Api
  module V1
    class TodosController < BaseController
      FILTERS = %w[open today week upcoming overdue undated done cancelled all].freeze
      SORTS = %w[position due completed created].freeze
      DEFAULT_PER_PAGE = 50
      MAX_PER_PAGE = 200
      MAX_PAGE = 100_000
      DUE_TIME = /\A([01]\d|2[0-3]):([0-5]\d)\z/

      before_action :set_todo, only: [ :show, :update, :destroy, :toggle ]

      # filter: open (the default, as before), today, week, upcoming,
      # overdue, undated, done, cancelled or all. list_id (one of the user's
      # lists, or "none") and priority narrow the list and meta.counts;
      # open_count and overdue_count stay across all the user's todos, as
      # before. Pagination is opt-in (page / per_page).
      def index
        filter = choice_param(:filter, FILTERS, default: "open")
        sort = choice_param(:sort, SORTS, default: "position")
        page, per_page = page_params
        scope = narrowed(current_user.todos)
        counts = filter_counts(scope)

        todos = sorted(filtered(scope, filter), sort).includes(:todo_list, :subtasks)
        todos = todos.offset((page - 1) * per_page).limit(per_page) if page

        meta = {
          open_count: current_user.todos.open.count,
          overdue_count: current_user.todos.overdue.count,
          total_count: counts[filter],
          counts: counts
        }
        meta.merge!(page: page, per_page: per_page) if page
        render json: { todos: todos.map { |todo| Serialize.todo(todo) }, meta: meta }
      end

      def show
        render json: { todo: Serialize.todo(@todo) }
      end

      def create
        todo = current_user.todos.new
        todo.assign_attributes(todo_attributes(todo))
        if todo.save
          render json: { todo: Serialize.todo(todo) }, status: :created
        else
          render_errors(todo)
        end
      end

      # Only the keys sent change.
      def update
        @todo.assign_attributes(todo_attributes(@todo))
        if @todo.save
          render json: { todo: Serialize.todo(@todo) }
        else
          render_errors(@todo)
        end
      end

      # As on the web: its subtasks stay, without a parent, and its focus
      # sessions stay in the history, unlinked.
      def destroy
        @todo.destroy!
        head :no_content
      end

      # With done=true|false the todo ends up in that state however many times
      # the request is sent, so a stale screen or a retried request cannot
      # reopen a finished todo. Without it the old done <-> pending flip runs,
      # for older clients.
      def toggle
        if @todo.update(status: toggled_status(@todo, boolean_param(:done)))
          render json: { id: @todo.id, status: @todo.status, completed_at: @todo.completed_at, todo: Serialize.todo(@todo) }
        else
          render_errors(@todo)
        end
      end

      private

      def set_todo
        @todo = current_user.todos.find(params[:id])
      end

      # done=false only reopens a done todo; in_progress and cancelled are
      # already "not done" and keep their status.
      def toggled_status(todo, done)
        case done
        when nil   then todo.done? ? "pending" : "done"
        when true  then "done"
        else            todo.done? ? "pending" : todo.status
        end
      end

      # list_id: a list of the user's (archived ones too; 404 otherwise) or
      # "none" for the todos in no list. An empty list_id is ignored, as before.
      def narrowed(scope)
        list_id = params[:list_id]
        if list_id == "none"
          scope = scope.where(todo_list_id: nil)
        elsif !list_id.nil? && list_id != ""
          scope = scope.where(todo_list_id: owned_id_param(current_user.todo_lists, :list_id))
        end
        priority = choice_param(:priority, Todo::PRIORITIES)
        priority ? scope.where(priority: priority) : scope
      end

      def filtered(scope, filter)
        case filter
        when "today"     then scope.due_today
        when "week"      then scope.due_this_week
        when "upcoming"  then scope.due_upcoming
        when "overdue"   then scope.overdue
        when "undated"   then scope.undated
        when "done"      then scope.done
        when "cancelled" then scope.cancelled
        when "all"       then scope
        else                  scope.open
        end
      end

      # position: the web's order (manual position, then oldest first),
      # unchanged. due: soonest due first, undated last. completed: most
      # recently completed first. created: newest first.
      def sorted(scope, sort)
        todos = Todo.arel_table
        case sort
        when "due"       then scope.order(todos[:due_at].asc.nulls_last).ordered
        when "completed" then scope.order(todos[:completed_at].desc.nulls_last, id: :desc)
        when "created"   then scope.order(created_at: :desc, id: :desc)
        else                  scope.ordered.order(due_at: :asc, created_at: :desc)
        end
      end

      # How many todos each filter would list, narrowed like the list, in a
      # single query: COUNT(*) FILTER (WHERE <the filter's conditions>).
      def filter_counts(scope)
        columns = FILTERS.map do |filter|
          conditions = filtered(Todo.unscoped, filter).arel.constraints
          conditions.empty? ? Arel.star.count : Arel.star.count.filter(Arel::Nodes::And.new(conditions))
        end
        FILTERS.zip(scope.pick(*columns)).to_h
      end

      # Opt-in: with page or per_page, page n (from 1) of per_page todos
      # (default 50, at most 200). Without either, every matching todo.
      def page_params
        return [ nil, nil ] unless params.key?(:page) || params.key?(:per_page)

        page = integer_param(:page) || 1
        per_page = integer_param(:per_page) || DEFAULT_PER_PAGE
        raise InvalidParameter, :page unless page.between?(1, MAX_PAGE)
        raise InvalidParameter, :per_page unless per_page.between?(1, MAX_PER_PAGE)

        [ page, per_page ]
      end

      # Only the keys sent change; null clears an optional field. The list
      # and the goal must be the user's (404 otherwise); an archived list is
      # accepted, as on the web.
      def todo_attributes(todo)
        attrs = params.permit(:title, :body, :priority, :status).to_h
        attrs[:position] = required_integer_param(:position) if params.key?(:position)
        attrs[:todo_list_id] = owned_id_param(current_user.todo_lists, :todo_list_id) if params.key?(:todo_list_id)
        attrs[:goal_id] = owned_id_param(current_user.goals, :goal_id) if params.key?(:goal_id)
        attrs.merge(due_attributes(todo))
      end

      # The due date comes either as due_at (an instant; a bare date is a
      # date-only due) or as due_date plus an optional due_time ("HH:MM" in
      # the user's zone). Without a time the todo is due all day: it is
      # stored as 23:59:59 (Todo.end_of_due_day), so it is not overdue during
      # its own day. On an update, due_date alone keeps the todo's time of
      # day, and due_time alone keeps its date.
      def due_attributes(todo)
        sent = %i[due_at due_date due_time].select { |key| params.key?(key) }
        return {} if sent.empty?
        raise InvalidParameter, :due_at if sent.include?(:due_at) && sent.size > 1
        return { due_at: due_at_param } if sent == [ :due_at ]

        date = params.key?(:due_date) ? date_param(:due_date) : todo.due_date
        time = params.key?(:due_time) ? due_time_param : time_of_day(todo)
        if date.nil?
          # A time needs a day to be on.
          raise InvalidParameter, :due_time if params.key?(:due_time) && time

          return { due_at: nil }
        end
        { due_at: time ? Time.zone.local(date.year, date.month, date.day, *time) : Todo.end_of_due_day(date) }
      end

      def due_at_param
        due_at = datetime_param(:due_at)
        return due_at unless due_at && params[:due_at].match?(ISO_DATE)

        Todo.end_of_due_day(due_at.to_date)
      end

      def due_time_param
        value = params[:due_time]
        return nil if value.nil? || value == ""

        match = DUE_TIME.match(value) if value.is_a?(String)
        raise InvalidParameter, :due_time unless match

        [ match[1].to_i, match[2].to_i ]
      end

      def time_of_day(todo)
        [ todo.due_at.hour, todo.due_at.min ] if todo.due_at && !todo.due_date_only?
      end
    end
  end
end
