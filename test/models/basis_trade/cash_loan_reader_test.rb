require "test_helper"

class BasisTrade::CashLoanReaderTest < ActiveSupport::TestCase
  SAFE_ADDRESS = "0xe046ef5e90f6d0a6b9dbb4d98541986b39c95836".freeze

  setup do
    @reader = BasisTrade::CashLoanReader.new
  end

  test "reads the current debtUsd from the official LendGateway account data" do
    debt_usd = 248_125_000
    response = "0x#{encoded_word(1)}#{encoded_word(debt_usd)}#{encoded_word(3)}#{encoded_word(4)}#{encoded_word(5)}"
    @reader.expects(:rpc_call).with(
      "eth_call",
      [
        {
          to: BasisTrade::CashLoanReader::LEND_GATEWAY_ADDRESS,
          data: "0x#{BasisTrade::CashLoanReader::GET_ACCOUNT_DATA_SELECTOR}#{encoded_address(SAFE_ADDRESS)}"
        },
        "latest"
      ]
    ).returns(response)

    assert_equal BigDecimal("248.125"), @reader.borrowed_usdc(vault_address: SAFE_ADDRESS)
  end

  test "rejects account data responses without all five words" do
    @reader.expects(:rpc_call).returns("0x#{encoded_word(1)}#{encoded_word(2)}")

    error = assert_raises(RuntimeError) { @reader.borrowed_usdc(vault_address: SAFE_ADDRESS) }
    assert_equal "Unexpected Ether.fi Cash LendGateway account data response", error.message
  end

  test "requires a valid safe address" do
    assert_raises(ArgumentError) { @reader.borrowed_usdc(vault_address: "") }
    assert_raises(ArgumentError) { @reader.borrowed_usdc(vault_address: "not-an-address") }
  end

  private
    def encoded_address(address)
      address.delete_prefix("0x").rjust(64, "0")
    end

    def encoded_word(value)
      value.to_s(16).rjust(64, "0")
    end
end
