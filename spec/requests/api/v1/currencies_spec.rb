require "rails_helper"

RSpec.describe "Api::V1::Currencies", type: :request do
  let(:user) { create(:user) }
  let(:auth) { { "Authorization" => "Bearer #{user.api_token}" } }

  def body = JSON.parse(response.body)

  it "401s without a token" do
    get api_v1_currencies_path

    expect(response).to have_http_status(:unauthorized)
    expect(body).to eq("error" => "unauthorized", "code" => "unauthorized")
  end

  it "lists the offered currencies with what an amount field needs" do
    get api_v1_currencies_path, headers: auth

    expect(response).to have_http_status(:ok)
    expect(body["default_currency"]).to eq("TRY")
    expect(body["currencies"].map { |c| c["code"] }).to eq(%w[TRY USD EUR GBP GAU])
    expect(body["currencies"].first).to eq(
      "code" => "TRY", "name" => "Turkish lira", "symbol" => "₺", "symbol_first" => true,
      "subunit_to_unit" => 100, "decimal_places" => 2
    )
    expect(body["currencies"].last).to eq(
      "code" => "GAU", "name" => "Gram gold", "symbol" => "gr", "symbol_first" => false,
      "subunit_to_unit" => 1, "decimal_places" => 0
    )
  end

  it "adds the other currencies the user already uses, leaving out codes Money does not know" do
    user.update!(currency: "CHF")
    create(:account, user: user, currency: "JPY")
    create(:account, user: user).update_column(:currency, "XYZ")
    create(:account, currency: "KWD")

    get api_v1_currencies_path, headers: auth

    expect(body["currencies"].map { |c| c["code"] }).to eq(%w[TRY USD EUR GBP GAU CHF JPY])
    expect(body["currencies"].find { |c| c["code"] == "JPY" }).to include("name" => "Japanese Yen", "decimal_places" => 0)
    expect(body["default_currency"]).to eq("CHF")
  end

  it "names the currencies in the user's language" do
    user.update!(locale: "tr")

    get api_v1_currencies_path, headers: auth

    expect(body["currencies"].map { |c| c["name"] }).to eq([ "Türk lirası", "ABD doları", "Euro", "İngiliz sterlini", "Gram altın" ])
  end
end
