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
    category = @family.categories.create!(name: "Csp Test Rent #{SecureRandom.hex(3)}", color: "#ff0000", lucide_icon: "shapes")
    category.update!(csp_bucket: "fixed_costs")

    get csp_path

    assert_response :success
    assert_match(/Spending Plan/i, response.body)
  end

  test "saves bucket assignments via patch" do
    category = @family.categories.create!(name: "Csp Test Fun #{SecureRandom.hex(3)}", color: "#00ff00", lucide_icon: "shapes")

    patch csp_buckets_path, params: { category_buckets: { category.id => "guilt_free" } }

    assert_redirected_to csp_path(month_year: Budget.date_to_param(Date.current))
    assert_equal "guilt_free", category.reload.csp_bucket
  end

  test "saves account transfer bucket assignments via patch" do
    account = @family.accounts.create!(name: "Csp Test HSA #{SecureRandom.hex(3)}", balance: 0, currency: "USD", accountable: Depository.new)

    patch csp_buckets_path, params: { account_buckets: { account.id => "savings" } }

    assert_redirected_to csp_path(month_year: Budget.date_to_param(Date.current))
    assert_equal "savings", account.reload.csp_bucket
  end

  test "rejects unknown account buckets" do
    account = @family.accounts.create!(name: "Csp Test HSA #{SecureRandom.hex(3)}", balance: 0, currency: "USD", accountable: Depository.new)

    patch csp_buckets_path, params: { account_buckets: { account.id => "nope" } }

    # BadRequest is rescuable, so the test env renders it as a 400 response
    # rather than raising.
    assert_response :bad_request
    assert_nil account.reload.csp_bucket
  end

  test "saves manual take-home pay" do
    patch csp_take_home_pay_path, params: { take_home_pay: "8500.00" }

    assert_redirected_to csp_path(month_year: Budget.date_to_param(Date.current))
    assert_equal 8500, @family.reload.csp_take_home_pay
  end

  test "clears manual take-home pay when blank" do
    @family.update!(csp_take_home_pay: 8500)

    patch csp_take_home_pay_path, params: { take_home_pay: "" }

    assert_redirected_to csp_path(month_year: Budget.date_to_param(Date.current))
    assert_nil @family.reload.csp_take_home_pay
  end

  test "rejects invalid take-home pay" do
    patch csp_take_home_pay_path, params: { take_home_pay: "abc" }

    assert_redirected_to csp_path(month_year: Budget.date_to_param(Date.current))
    assert_nil @family.reload.csp_take_home_pay
  end
end
