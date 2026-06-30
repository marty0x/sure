require "test_helper"

class BasisTrade::LiveSnapshotBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "uses spot wallet value, lighter notional for short leg, keeps live rewards at zero, and captures reward basis metadata" do
    @family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
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
      funding_accrued: BigDecimal("0.63"),
      accounts: [ { index: "730104", total_asset_value: BigDecimal("2850.99") } ]
    )

    result = described_class.new(family: @family).call

    assert result.configured
    assert_nil result.error
    assert_equal 709_544, result.snapshot[:spot_leg_cents]
    assert_equal 711_299, result.snapshot[:short_leg_cents]
    assert_equal 63, result.snapshot[:funding_accrued_cents]
    assert_equal 0, result.snapshot[:rewards_accrued_cents]
    assert_equal BigDecimal("2850.99"), result.snapshot.dig(:metadata, :lighter, :total_account_value)
    assert_equal BigDecimal("2850.99"), result.snapshot.dig(:metadata, :lighter, :total_collateral)
    assert_equal BigDecimal("2.4901"), result.snapshot.dig(:metadata, :rewards_basis, :eth_balance)
    assert_equal BigDecimal("2850.93"), result.snapshot.dig(:metadata, :rewards_basis, :eth_price_usd)
    assert_equal BigDecimal("84.92"), result.snapshot.dig(:metadata, :rewards_basis, :usdc_balance)
  end

  test "keeps live rewards at zero even when an initial snapshot exists" do
    @family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
    )

    @family.basis_trade_snapshots.create!(
      recorded_at: Time.zone.parse("2026-06-20 00:00:00"),
      spot_leg_cents: 7_000_000,
      short_leg_cents: -7_000_000,
      funding_accrued_cents: 0,
      rewards_accrued_cents: 0,
      currency: "USD"
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
      funding_accrued: BigDecimal("0.63"),
      accounts: [ { index: "730104", total_asset_value: BigDecimal("2850.99") } ]
    )

    result = described_class.new(family: @family).call

    assert_equal 0, result.snapshot[:rewards_accrued_cents]
  end

  private

    def described_class
      BasisTrade::LiveSnapshotBuilder
    end
end
