class JournalEntriesController < ApplicationController
  RANGES = %w[1d 7d 30d 6mo 1y all].freeze
  DEFAULT_RANGE = "30d".freeze

  before_action :set_entry, only: [ :show, :edit, :update, :destroy ]

  def index
    @range = RANGES.include?(params[:range]) ? params[:range] : DEFAULT_RANGE
    @range_start = range_start_for(@range)

    scope = current_user.journal_entries.recent
    scope = scope.where(date: @range_start..Date.current) if @range_start
    @entries = scope.limit(180)

    mood_scope = current_user.journal_entries.where.not(mood: nil)
    mood_scope = mood_scope.where(date: @range_start..Date.current) if @range_start
    @mood_data = mood_scope.group(:mood).count
  end

  def show
  end

  def new
    @entry = current_user.journal_entries.new(date: Date.current)
  end

  def create
    @entry = current_user.journal_entries.new(entry_params)
    if @entry.save
      redirect_to journal_entry_path(@entry), notice: t("flash.saved")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(entry_params)
      redirect_to journal_entry_path(@entry), notice: t("flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to journal_entries_path, notice: t("flash.deleted")
  end

  private

  def set_entry
    @entry = current_user.journal_entries.find(params[:id])
  end

  def entry_params
    params.require(:journal_entry).permit(:date, :title, :body, :mood, :weather, :energy_level, :gratitude, :tags, attachments: [])
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
