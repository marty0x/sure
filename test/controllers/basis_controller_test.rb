require "test_helper"

class BasisControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in @user
    ensure_tailwind_build
  end

  test "redirects users without preview access" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => false))

    get basis_path

    assert_redirected_to root_path
    assert_match(/preview/i, flash[:alert])
  end

  test "renders basis page for preview-enabled users" do
    get basis_path

    assert_response :success
    assert_match(/Basis/i, response.body)
    assert_select "a[href='#{basis_path}']"
  end

  test "renders empty state when no snapshots exist" do
    get basis_path

    assert_response :success
    assert_match(/No basis snapshots yet/i, response.body)
  end

  test "renders live basis balances when direct sources are configured" do
    @user.family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
    )
    @user.family.basis_trade_snapshots.create!(
      recorded_at: Time.zone.parse("2026-06-20 00:00:00"),
      spot_leg_cents: 7_000_000,
      short_leg_cents: -7_000_000,
      funding_accrued_cents: 0,
      rewards_accrued_cents: 0,
      currency: "USD",
      metadata: {
        rewards_basis: {
          eth_balance: "2.4900",
          eth_price_usd: "2800.0",
          usdc_balance: "0"
        }
      }
    )

    BasisTrade::OptimismWalletValuator.any_instance.stubs(:value).returns(
      {
        total_value: BigDecimal("7095.44"),
        tokens: [ { symbol: "weETH", balance: BigDecimal("2.4901"), price_usd: BigDecimal("2850.93") } ]
      },
      {
        total_value: BigDecimal("84.92"),
        tokens: [ { symbol: "USDC", balance: BigDecimal("84.92"), price_usd: BigDecimal("1.0") } ]
      }
    )
    Provider::Lighter.any_instance.stubs(:total_account_value_for_l1_address).returns(
      total_account_value: BigDecimal("2850.99"),
      total_collateral: BigDecimal("2850.99"),
      total_position_notional: BigDecimal("7112.99"),
      funding_accrued: BigDecimal("17.40"),
      accounts: [ { index: "730104", total_asset_value: BigDecimal("2850.99") } ]
    )

    get basis_path

    assert_response :success
    assert_match(/Live balances/i, response.body)
    assert_match(/Spot wallet balances/i, response.body)
    assert_match(/Perps account values/i, response.body)
    assert_match(/weETH/i, response.body)
    assert_match(/Account 730104/i, response.body)
    assert_match(/\$10,048\.75/, response.body)
    assert_match(/\$7,095\.44/, response.body)
    assert_match(/\$2,850\.99 USD/, response.body)
    assert_match(/\$7,112\.99/, response.body)
    assert_match(/\$17\.40/, response.body)
    assert_match(/\$84\.92/, response.body)
    assert_includes response.body, "text-success"
    assert_includes response.body, "text-destructive"
  end

  test "renders basis configuration guidance when direct sources are not configured" do
    BasisTrade::CashLoanUpdater.expects(:new).never

    get basis_path

    assert_response :success
    assert_match(/Settings → Preferences/i, response.body)
  end

  test "refreshes ether.fi Credit on page load when a spot vault is configured" do
    @user.family.update!(basis_long_address: "0x1111111111111111111111111111111111111111")

    updater = mock
    updater.expects(:call).once.returns(
      BasisTrade::CashLoanUpdater::Result.new(configured: true, updated: true, balance: BigDecimal("123.45"))
    )
    BasisTrade::CashLoanUpdater.expects(:new).with(family: @user.family).returns(updater)

    BasisTrade::LiveSnapshotBuilder.any_instance.stubs(:call).returns(
      BasisTrade::LiveSnapshotBuilder::Result.new(configured: true, snapshot: {
        recorded_at: Time.current,
        currency: "USD",
        spot_leg_cents: 0,
        short_leg_cents: 0,
        funding_accrued_cents: 0,
        rewards_accrued_cents: 0,
        metadata: {}
      })
    )

    get basis_path

    assert_response :success
  end

  test "renders live basis error when direct source refresh fails" do
    @user.family.update!(basis_long_address: "0x1111111111111111111111111111111111111111")
    BasisTrade::LiveSnapshotBuilder.any_instance.stubs(:call).returns(
      BasisTrade::LiveSnapshotBuilder::Result.new(configured: true, error: "boom")
    )

    get basis_path

    assert_response :success
    assert_match(/Live balance refresh failed: boom/i, response.body)
  end

  test "renders chart payload without legacy leg toggles when snapshots exist" do
    BasisTradeSnapshot.create!(
      family: @user.family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      spot_leg_cents: 1_500_000,
      short_leg_cents: -25_000,
      funding_accrued_cents: 12_000,
      rewards_accrued_cents: 4_000,
      currency: "USD",
      metadata: {
        lighter: {
          total_account_value: "280.0"
        }
      }
    )

    get basis_path

    assert_response :success
    assert_select "[data-controller='basis-chart']"
    assert_select "[data-basis-chart-payload-value]"
    assert_match(/Basis account value/i, response.body)
    assert_no_match(/basis-toggle-spot/, response.body)
    assert_no_match(/basis_leg_spot/, response.body)
  end
end
