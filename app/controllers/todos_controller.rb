class TodosController < ApplicationController
  before_action :set_todo, only: [ :show, :edit, :update, :destroy, :toggle, :reorder ]

  def index
    @lists = current_user.todo_lists.active.ordered

    scope = current_user.todos.includes(:todo_list)
    scope = case params[:filter]
    when "today"    then scope.due_today
    when "week"     then scope.due_this_week
    when "overdue"  then scope.overdue
    when "done"     then scope.done
    else                  scope.open
    end
    scope = scope.where(todo_list_id: params[:list_id]) if params[:list_id].present?
    scope = scope.where(priority: params[:priority])     if params[:priority].present?

    @todos = scope.ordered.order(due_at: :asc, created_at: :desc)
    @filter = params[:filter] || "open"
  end

  def show
  end

  def new
    @todo = current_user.todos.new(status: "pending", priority: "medium")
    @lists = current_user.todo_lists.active.ordered
  end

  def create
    @todo = current_user.todos.new(todo_params)
    if @todo.save
      redirect_to todos_path, notice: t("flash.saved")
    else
      @lists = current_user.todo_lists.active.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lists = current_user.todo_lists.active.ordered
  end

  def update
    if @todo.update(todo_params)
      redirect_to todos_path, notice: t("flash.updated")
    else
      @lists = current_user.todo_lists.active.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @todo.destroy
    redirect_to todos_path, notice: t("flash.deleted")
  end

  def toggle
    @todo.update(status: @todo.done? ? "pending" : "done")
    redirect_back fallback_location: todos_path
  end

  def reorder
    @todo.update(position: params[:position].to_i)
    head :ok
  end

  private

  def set_todo
    @todo = current_user.todos.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(:title, :body, :todo_list_id, :due_at, :priority, :status)
  end
end
