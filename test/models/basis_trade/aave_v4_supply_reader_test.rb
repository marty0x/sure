require "test_helper"

class BasisTrade::AaveV4SupplyReaderTest < ActiveSupport::TestCase
  SAFE_ADDRESS = "0x00000000000000000000000000000000000000AA".freeze

  setup do
    @reader = BasisTrade::AaveV4SupplyReader.new
  end

  test "reads a Cash Safe's supplied weETH from the Aave v4 Spoke" do
    asset_id = "5".rjust(64, "0")
    reserve_id = "12".rjust(64, "0")
    supplied_weeth = (2_490_100_000_000_000_000).to_s(16).rjust(64, "0")

    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::HUB_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_ASSET_ID_SELECTOR}#{BasisTrade::AaveV4SupplyReader::WEETH_ADDRESS.delete_prefix('0x').downcase.rjust(64, '0')}"
        },
        "latest"
      ]
    ).returns("0x#{asset_id}")
    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::SPOKE_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_RESERVE_ID_SELECTOR}#{BasisTrade::AaveV4SupplyReader::HUB_ADDRESS.delete_prefix('0x').downcase.rjust(64, '0')}#{asset_id}"
        },
        "latest"
      ]
    ).returns("0x#{reserve_id}")
    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::SPOKE_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_USER_SUPPLIED_ASSETS_SELECTOR}#{reserve_id}#{SAFE_ADDRESS.delete_prefix('0x').downcase.rjust(64, '0')}"
        },
        "latest"
      ]
    ).returns("0x#{supplied_weeth}")

    assert_equal BigDecimal("2.4901"), @reader.supplied_balance(token_address: BasisTrade::AaveV4SupplyReader::WEETH_ADDRESS, safe_address: SAFE_ADDRESS)
  end

  test "reads a Cash Safe's supplied native Optimism USDC from the Aave v4 Spoke" do
    asset_id = "0".rjust(64, "0")
    reserve_id = "0".rjust(64, "0")
    supplied_usdc = (84_920_000).to_s(16).rjust(64, "0")
    usdc_address = BasisTrade::AaveV4SupplyReader::OPTIMISM_USDC_ADDRESS

    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::HUB_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_ASSET_ID_SELECTOR}#{usdc_address.delete_prefix('0x').downcase.rjust(64, '0')}"
        },
        "latest"
      ]
    ).returns("0x#{asset_id}")
    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::SPOKE_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_RESERVE_ID_SELECTOR}#{BasisTrade::AaveV4SupplyReader::HUB_ADDRESS.delete_prefix('0x').downcase.rjust(64, '0')}#{asset_id}"
        },
        "latest"
      ]
    ).returns("0x#{reserve_id}")
    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::AaveV4SupplyReader::SPOKE_ADDRESS,
          data: "0x#{BasisTrade::AaveV4SupplyReader::GET_USER_SUPPLIED_ASSETS_SELECTOR}#{reserve_id}#{SAFE_ADDRESS.delete_prefix('0x').downcase.rjust(64, '0')}"
        },
        "latest"
      ]
    ).returns("0x#{supplied_usdc}")

    assert_equal BigDecimal("84.92"), @reader.supplied_balance(token_address: usdc_address, safe_address: SAFE_ADDRESS)
  end

  test "does not query Aave v4 for unverified tokens" do
    @reader.expects(:rpc_call).never

    assert_equal BigDecimal("0"), @reader.supplied_balance(
      token_address: "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
      safe_address: SAFE_ADDRESS
    )
  end

  test "raises when the Aave v4 RPC result is malformed" do
    @reader.stubs(:rpc_call).returns("0xnot-hex")

    assert_raises(RuntimeError) do
      @reader.supplied_balance(token_address: BasisTrade::AaveV4SupplyReader::WEETH_ADDRESS, safe_address: SAFE_ADDRESS)
    end
  end
end
