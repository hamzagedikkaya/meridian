class JournalEntriesController < ApplicationController
  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @entries = current_user.journal_entries.recent.limit(60)
    @mood_data = current_user.journal_entries.where.not(mood: nil)
                             .where(date: 30.days.ago.to_date..Date.current)
                             .group(:mood).count
  end

  def show
  end

  def new
    @entry = current_user.journal_entries.new(date: Date.current)
  end

  def create
    @entry = current_user.journal_entries.new(entry_params)
    if @entry.save
      redirect_to journal_entry_path(@entry), notice: "Entry saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(entry_params)
      redirect_to journal_entry_path(@entry), notice: "Entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to journal_entries_path, notice: "Entry deleted."
  end

  private

  def set_entry
    @entry = current_user.journal_entries.find(params[:id])
  end

  def entry_params
    params.require(:journal_entry).permit(:date, :title, :body, :mood, :weather, :energy_level, :gratitude, :tags, attachments: [])
  end
end
