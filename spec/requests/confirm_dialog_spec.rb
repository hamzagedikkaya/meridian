require "rails_helper"

# The styled confirm dialog lives in the layout and replaces Turbo's native
# window.confirm for every data-turbo-confirm action. Guard that it stays
# mounted on authenticated pages.
RSpec.describe "Confirm dialog", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "mounts the confirm dialog controller in the layout" do
    get finance_accounts_path
    expect(response.body).to include('data-controller="confirm"')
    expect(response.body).to include(I18n.t("common.confirm_title"))
  end
end
