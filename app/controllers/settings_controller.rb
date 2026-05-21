class SettingsController < ApplicationController
  def show
    redirect_to profile_settings_path
  end

  def profile
    render :profile
  end

  def update_profile
    attrs = profile_params.to_h
    if attrs["password"].blank?
      attrs.delete("password")
      attrs.delete("password_confirmation")
    end

    if current_user.update(attrs)
      bypass_sign_in(current_user) if attrs["password"].present?
      redirect_to profile_settings_path, notice: t("flash.updated")
    else
      render :profile, status: :unprocessable_entity
    end
  end

  def preferences
    render :preferences
  end

  def update_preferences
    if current_user.update(preferences_params)
      redirect_to preferences_settings_path, notice: t("flash.updated")
    else
      render :preferences, status: :unprocessable_entity
    end
  end

  def data
    @last_backup = current_user.backups.succeeded.recent.first
    render :data
  end

  private

  def profile_params
    params.require(:user).permit(:name, :email, :avatar, :password, :password_confirmation)
  end

  def preferences_params
    params.require(:user).permit(:timezone, :currency, :locale, :theme_preference, :weekly_review_day)
  end
end
