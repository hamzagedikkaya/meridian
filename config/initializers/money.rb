Money::Currency.register(
  iso_code:              "GAU",
  name:                  "Gram Altın",
  symbol:                "gr",
  subunit:               "Gram",
  subunit_to_unit:       1,
  symbol_first:          false,
  smallest_denomination: 1
)

MoneyRails.configure do |config|
  config.default_currency = :try

  config.locale_backend = :i18n
  config.rounding_mode = BigDecimal::ROUND_HALF_UP
  config.no_cents_if_whole = false
end
