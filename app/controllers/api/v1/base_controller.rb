module Api
  module V1
    class BaseController < ActionController::API
      include UserTimeZoneAndLocale
      include ClientAddress

      # A request parameter with a value the endpoint cannot use (a "done" that
      # is not a boolean, a "count" that is not a whole number).
      class InvalidParameter < StandardError
        attr_reader :param

        def initialize(param)
          @param = param.to_s
          super("invalid value for #{@param}")
        end
      end

      # A date parameter that is not exactly YYYY-MM-DD, or names a day that
      # does not exist.
      class InvalidDate < StandardError
        attr_reader :param

        def initialize(param)
          @param = param.to_s
          super("invalid date for #{@param}")
        end
      end

      # A datetime parameter that is not an ISO 8601 date and time, or names a
      # day, time or UTC offset that does not exist.
      class InvalidDatetime < StandardError
        attr_reader :param

        def initialize(param)
          @param = param.to_s
          super("invalid datetime for #{@param}")
        end
      end

      BOOLEAN_PARAM_VALUES = { true => true, false => false, "true" => true, "false" => false, "1" => true, "0" => false }.freeze
      ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
      # YYYY-MM-DD, optionally followed by Thh:mm[:ss[.fraction]] and an
      # offset (Z, ±hh, ±hhmm or ±hh:mm).
      ISO_DATETIME = /\A(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?(?:Z|[+-](\d{2})(?::?(\d{2}))?)?)?\z/i
      HEX_COLOR = /\A#\h{6}\z/

      before_action :authenticate_api_user!
      # Declared after authentication so it knows the user; a failed token
      # halts the chain before it runs.
      around_action :switch_time_zone_and_locale
      # PostgreSQL refuses a string with a NUL byte ("string contains null
      # byte", a 500), wherever the value goes.
      before_action :refuse_null_bytes

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
      # Every *_cents column is a 4-byte integer; an oversized value raises at
      # save time instead of failing validation.
      rescue_from ActiveModel::RangeError, with: :render_value_out_of_range
      rescue_from InvalidParameter, with: :render_invalid_parameter
      rescue_from InvalidDate, with: :render_invalid_date
      rescue_from InvalidDatetime, with: :render_invalid_datetime

      private

      attr_reader :current_user

      def authenticate_api_user!
        @current_user = User.find_by(api_token: bearer_token) if bearer_token.present?
        return if @current_user

        render json: { error: "unauthorized", code: "unauthorized" }, status: :unauthorized
      end

      def bearer_token
        request.authorization.to_s[/\ABearer (.+)\z/, 1]
      end

      def switch_time_zone_and_locale(&action)
        with_user_time_zone_and_locale(current_user, &action)
      end

      # rescue_from handlers run outside the callback chain
      # (ActionController::Rescue wraps process_action), so without this an
      # error rendered by a handler would be worded in the default locale.
      def rescue_with_handler(exception)
        with_user_time_zone_and_locale(current_user) { super }
      end

      def render_not_found
        render json: { error: "not_found", code: "not_found" }, status: :not_found
      end

      # 422 invalid_parameter for the first parameter (query, body or path)
      # holding a string with "\u0000", named by its top-level key. An
      # endpoint that cleans a parameter itself lists it in
      # #null_byte_cleaned_params.
      def refuse_null_bytes
        name, _ = request.parameters.except(*null_byte_cleaned_params).find { |_, value| null_byte?(value) }
        render_invalid_parameter(InvalidParameter.new(name)) if name
      end

      def null_byte_cleaned_params
        []
      end

      def null_byte?(value)
        case value
        when String then value.include?("\u0000")
        when Hash then value.any? { |key, nested| null_byte?(key) || null_byte?(nested) }
        when Array then value.any? { |nested| null_byte?(nested) }
        else false
        end
      end

      # 422 for a record that failed validation. `errors` keeps the original
      # field => [full message] shape; `details` adds the machine-readable
      # error per field (blank, taken, too_long, ...) so a client can word or
      # translate the message itself. A +code+ other than validation_failed
      # names the error the client has to act on first (e.g. a wrong current
      # password) while `errors` still lists every field.
      def render_errors(record, code: :validation_failed)
        render json: {
          errors: record.errors.to_hash(true),
          code: code.to_s,
          details: record.errors.details
        }, status: :unprocessable_content
      end

      # The body of every rate limit refusal (rate_limit with:).
      def render_too_many_requests
        render json: { error: "too_many_requests", code: "too_many_requests" }, status: :too_many_requests
      end

      # 422 for anything that is not a model validation failure. The message
      # still goes out as {errors: {field => [message]}}, the shape every
      # client already reads; `code` is the stable part to branch on.
      def render_unprocessable(code, message:, field: :base, **extra)
        render json: { errors: { field => [ message ] }, code: code.to_s, **extra }, status: :unprocessable_content
      end

      def render_record_invalid(exception)
        render_errors(exception.record)
      end

      def render_value_out_of_range
        render_unprocessable(:value_out_of_range, message: I18n.t("api.errors.value_out_of_range"))
      end

      def render_invalid_parameter(exception)
        render_unprocessable(:invalid_parameter,
          field: exception.param,
          message: I18n.t("api.errors.invalid_parameter", param: exception.param),
          param: exception.param)
      end

      def render_invalid_date(exception)
        render_unprocessable(:invalid_date,
          field: exception.param,
          message: I18n.t("api.errors.invalid_date"),
          param: exception.param)
      end

      def render_invalid_datetime(exception)
        render_unprocessable(:invalid_datetime,
          field: exception.param,
          message: I18n.t("api.errors.invalid_datetime"),
          param: exception.param)
      end

      # Strict boolean: nil when the parameter is absent or null, otherwise
      # true/false/"true"/"false"/1/0. Anything else is a 422 rather than
      # ActiveModel's cast, which reads "maybe" as true.
      def boolean_param(name)
        value = params[name]
        return nil if value.nil?

        value = value.downcase if value.is_a?(String)
        value = value.to_s if value.is_a?(Integer)
        BOOLEAN_PARAM_VALUES.fetch(value) { raise InvalidParameter, name }
      end

      # boolean_param for a key that was sent and cannot be null (a flag such
      # as `archived` or `all_day`): 422 invalid_parameter for null too.
      def required_boolean_param(name)
        value = boolean_param(name)
        raise InvalidParameter, name if value.nil?

        value
      end

      # Whole number from a JSON number or a form string; nil when absent or
      # null, 422 for anything else (1.5, "abc", ""). +from+ is the params
      # to read, for an endpoint that also takes a nested body.
      def integer_param(name, from: params)
        value = from[name]
        return nil if value.nil?
        return value if value.is_a?(Integer)
        return value.strip.to_i if value.is_a?(String) && value.strip.match?(/\A[+-]?\d+\z/)

        raise InvalidParameter, name
      end

      # integer_param for a key that was sent and cannot be null (a
      # `position`): 422 invalid_parameter for null too.
      def required_integer_param(name)
        integer_param(name) || raise(InvalidParameter, name)
      end

      # A lenient number (contract 1.6: cast, never refused): a JSON number or
      # a string, read as String#to_i reads it ("3abc" is 3), and clamped to
      # +range+. nil when absent, blank, or a list, an object or anything else
      # that is not a number or a string, so the caller's default applies.
      def lenient_integer_param(name, range: nil)
        value = params[name]
        number = case value
        when Integer then value
        when Float then value.finite? ? value.to_i : nil
        when String then value.strip.empty? ? nil : value.to_i
        end
        number && range ? number.clamp(range) : number
      end

      # A string, or nil when absent or null; 422 invalid_parameter for a
      # number, a list or an object. +from+ as for integer_param.
      def string_param(name, from: params)
        value = from[name]
        raise InvalidParameter, name unless value.nil? || value.is_a?(String)

        value
      end

      # Calendar date from exactly "YYYY-MM-DD"; nil when absent, null or "",
      # 422 invalid_date for anything else, an impossible day included.
      # Date.iso8601 alone would also read "2026-10" or "20261004".
      def date_param(name)
        value = params[name]
        return nil if value.nil? || value == ""
        raise InvalidDate, name unless value.is_a?(String) && value.match?(ISO_DATE)

        Date.iso8601(value)
      rescue Date::Error
        raise InvalidDate, name
      end

      # Instant from an ISO 8601 date and time in the request's zone (the
      # user's): "2026-10-05T09:00:00+03:00" or "...Z" as sent, a time without
      # an offset as the user's wall clock, a bare date as 00:00 that day. nil
      # when absent, null or ""; 422 invalid_datetime for anything else.
      # Time.zone.iso8601 alone rolls 2026-02-30 over into March and ignores
      # an offset it cannot use (+25:00), reading the wall clock instead.
      def datetime_param(name)
        value = params[name]
        return nil if value.nil? || value == ""

        match = ISO_DATETIME.match(value) if value.is_a?(String)
        raise InvalidDatetime, name unless match && real_datetime?(match)

        Time.zone.iso8601(value)
      rescue ArgumentError
        raise InvalidDatetime, name
      end

      def real_datetime?(match)
        year, month, day, hour, minute, second, offset_hours, offset_minutes = match.captures.map { |part| part&.to_i }
        Date.valid_date?(year, month, day) &&
          hour.to_i <= 23 && minute.to_i <= 59 && second.to_i <= 59 &&
          offset_hours.to_i <= 23 && offset_minutes.to_i <= 59
      end

      # One of +allowed+ (strings); +default+ when absent, null or "". 422
      # invalid_parameter for any other value.
      def choice_param(name, allowed, default: nil)
        value = params[name]
        return default if value.nil? || value == ""
        raise InvalidParameter, name unless value.is_a?(String) && allowed.include?(value)

        value
      end

      # The id in params[name] when it is a record of +scope+ (one of the
      # user's), nil when null or "". 404 for an id that is missing or
      # another user's; 422 invalid_parameter when it is not a whole number
      # ("12abc", 1.5, a list). owned_record_param returns the record itself.
      def owned_id_param(scope, name)
        owned_record_param(scope, name)&.id
      end

      def owned_record_param(scope, name)
        id = integer_param(name) unless params[name] == ""
        id && scope.find(id)
      end

      # Validates +record+ with its model rules plus the endpoint's own checks
      # (the block adds to record.errors) and saves it only when both pass, so
      # a client gets every field error in one 422.
      def save_checked(record)
        record.validate
        yield record if block_given?
        record.errors.empty? && record.save
      end

      # The web's color picker only lets "#RRGGBB" through (in the browser);
      # the models do not check it. Checked only when the value changes, so
      # an older row stays editable. nil/"" is allowed where the column means
      # "no color of its own" (a budget falls back to its category's).
      def check_color(record, attribute = :color, allow_blank: false)
        return unless record.will_save_change_to_attribute?(attribute)

        value = record[attribute]
        if value.blank?
          record.errors.add(attribute, :blank) unless allow_blank
        elsif !value.to_s.match?(HEX_COLOR)
          record.errors.add(attribute, :invalid)
        end
      end
    end
  end
end
