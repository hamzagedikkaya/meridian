class TodoListsController < ApplicationController
  before_action :set_list, only: [ :edit, :update, :destroy ]

  def index
    @lists = current_user.todo_lists.ordered
  end

  def new
    @list = current_user.todo_lists.new
  end

  def create
    @list = current_user.todo_lists.new(list_params)
    if @list.save
      redirect_to todo_lists_path, notice: "List created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @list.update(list_params)
      redirect_to todo_lists_path, notice: "List updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @list.destroy
    redirect_to todo_lists_path, notice: "List deleted."
  end

  private

  def set_list
    @list = current_user.todo_lists.find(params[:id])
  end

  def list_params
    params.require(:todo_list).permit(:name, :color, :icon, :position, :archived_at)
  end
end
