# Runs a request in the signed-in user's time zone and language.
#
# Both are scoped with blocks (Time.use_zone, I18n.with_locale) rather than
# assigned: I18n.locale and Time.zone are per-thread state that Rails never
# resets between requests, so an assignment made for one user would carry over
# to whichever request the same Puma thread serves next, including API
# requests from someone else.
#
# Without a user (sign-in page, health check, a failed token) the app defaults
# apply, for the same reason.
module UserTimeZoneAndLocale
  extend ActiveSupport::Concern

  private

  def with_user_time_zone_and_locale(user, &block)
    Time.use_zone(user&.time_zone || Time.zone_default) do
      I18n.with_locale(user&.preferred_locale || I18n.default_locale, &block)
    end
  end
end
