class SettingsController < ApplicationController
  def show
    redirect_to profile_settings_path
  end

  def profile
    render :profile
  end

  def update_profile
    if current_user.update(profile_params)
      redirect_to profile_settings_path, notice: "Profile updated."
    else
      render :profile, status: :unprocessable_entity
    end
  end

  def preferences
    render :preferences
  end

  def update_preferences
    if current_user.update(preferences_params)
      redirect_to preferences_settings_path, notice: "Preferences updated."
    else
      render :preferences, status: :unprocessable_entity
    end
  end

  def data
    @last_backup = current_user.backups.succeeded.recent.first
    render :data
  end

  def notifications
    render :notifications
  end

  private

  def profile_params
    params.require(:user).permit(:name, :email, :avatar)
  end

  def preferences_params
    params.require(:user).permit(:timezone, :currency, :locale, :theme_preference, :weekly_review_day)
  end
end
