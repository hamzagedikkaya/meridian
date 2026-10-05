# How many minor units make one major unit of a currency: 100 for TRY, USD,
# EUR and GBP, 1 for GAU (one gram of gold). Every *_cents amount is stored
# in these minor units. An unknown code reads as 100, as Money's own default.
module CurrencyUnit
  def self.subunit_to_unit(code)
    Money::Currency.find(code.to_s)&.subunit_to_unit || 100
  end
end
