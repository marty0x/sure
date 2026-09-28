require "test_helper"

class CspControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
    ensure_tailwind_build
    @family = @user.family
  end

  test "redirects users without preview access" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    get csp_path

    assert_redirected_to root_path
    assert_match(/preview/i, flash[:alert])
  end

  test "renders spending plan page for preview-enabled users" do
    get csp_path

    assert_response :success
    assert_match(/Spending Plan/i, response.body)
  end

  test "renders with bucket assignments" do
    category = @family.categories.create!(name: "Csp Test Rent #{SecureRandom.hex(3)}", color: "#ff0000", classification: "expense")
    category.update!(csp_bucket: "fixed_costs")

    get csp_path

    assert_response :success
    assert_match(/Spending Plan/i, response.body)
  end

  test "saves bucket assignments via patch" do
    category = @family.categories.create!(name: "Csp Test Fun #{SecureRandom.hex(3)}", color: "#00ff00", classification: "expense")

    patch csp_buckets_path, params: { csp_buckets: { category.id => "guilt_free" } }

    assert_redirected_to csp_path
    assert_equal "guilt_free", category.reload.csp_bucket
  end
end
