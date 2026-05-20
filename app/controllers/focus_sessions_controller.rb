class FocusSessionsController < ApplicationController
  def create
    duration = (params[:duration_minutes] || 25).to_i * 60
    session = current_user.focus_sessions.create!(
      todo_id: params[:todo_id].presence,
      duration_seconds: duration,
      started_at: Time.current,
      mode: params[:mode].presence || "focus"
    )
    render json: { id: session.id, duration_seconds: session.duration_seconds, started_at: session.started_at.iso8601 }
  end

  def update
    session = current_user.focus_sessions.find(params[:id])
    session.update!(completed_at: Time.current)
    render json: { ok: true }
  end
end
