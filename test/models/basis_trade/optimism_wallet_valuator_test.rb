require "test_helper"

class BasisTrade::OptimismWalletValuatorTest < ActiveSupport::TestCase
  test "adds supplied Aave balance to the configured token's direct wallet balance" do
    token = "0x5a7facb970d094b6c7ff1df0ea68d99e6e73cbff"
    valuator = BasisTrade::OptimismWalletValuator.new
    valuator.stubs(:token_symbol).with(token).returns("weETH")
    valuator.stubs(:token_decimals).with(token).returns(18)
    valuator.stubs(:token_balance).with("0x1111111111111111111111111111111111111111", token).returns(BigDecimal("0"))
    valuator.stubs(:fetch_prices).returns("optimism:#{token}" => "2850.93")

    result = valuator.value(
      address: "0x1111111111111111111111111111111111111111",
      token_addresses: [ token ],
      additional_balances: { token => BigDecimal("2.4901") }
    )

    assert_equal BigDecimal("2.4901"), result[:tokens].first[:balance]
    assert_equal BigDecimal("7099.100793"), result[:total_value]
  end
end
