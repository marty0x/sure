require "test_helper"

class BasisTrade::LiveSnapshotBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "uses spot wallet value, lighter notional for short leg, and lighter funding accrued" do
    @family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
    )

    BasisTrade::OptimismWalletValuator.any_instance.stubs(:value).returns(
      total_value: BigDecimal("11751.87"),
      tokens: [ { symbol: "weETH", balance: BigDecimal("4.123441") } ]
    )
    Provider::Lighter.any_instance.stubs(:total_account_value_for_l1_address).returns(
      total_account_value: BigDecimal("2865.89"),
      total_position_notional: BigDecimal("7112.99"),
      funding_accrued: BigDecimal("0.63"),
      accounts: [ { index: "730104", total_asset_value: BigDecimal("2865.89") } ]
    )

    result = described_class.new(family: @family).call

    assert result.configured
    assert_nil result.error
    assert_equal 1_175_187, result.snapshot[:spot_leg_cents]
    assert_equal 711_299, result.snapshot[:short_leg_cents]
    assert_equal 63, result.snapshot[:funding_accrued_cents]
    assert_equal BigDecimal("2865.89"), result.snapshot.dig(:metadata, :lighter, :total_account_value)
  end

  private

    def described_class
      BasisTrade::LiveSnapshotBuilder
    end
end
