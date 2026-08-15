require "test_helper"

class BasisTrade::CashLoanReaderTest < ActiveSupport::TestCase
  setup do
    @reader = BasisTrade::CashLoanReader.new
  end

  test "decodes Cash LendGateway total debt in USD" do
    # getAccountData returns five uint256 words. Word 2 is debtUsd, in 6 decimals.
    total_debt = 1_234_560_000.to_s(16).rjust(64, "0")
    response_words = Array.new(5) { "0".rjust(64, "0") }
    response_words[1] = total_debt
    @reader.stubs(:rpc_call).returns("0x#{response_words.join}")

    assert_equal BigDecimal("1234.56"), @reader.borrowing_usd(vault_address: "0x0000000000000000000000000000000000000abc")
  end

  test "calls Cash LendGateway getAccountData with the left-padded lowercased vault address" do
    vault = "0x00000000000000000000000000000000000000AA"
    expected_data = "0x#{BasisTrade::CashLoanReader::GET_ACCOUNT_DATA_SELECTOR}#{'aa'.rjust(64, '0')}"

    @reader.expects(:rpc_call).with(
      "eth_call",
      [ { to: BasisTrade::CashLoanReader::LEND_GATEWAY_ADDRESS, data: expected_data }, "latest" ]
    ).returns("0x#{'0'.rjust(64 * 5, '0')}")

    assert_equal BigDecimal("0"), @reader.borrowing_usd(vault_address: vault)
  end

  test "raises on a malformed response" do
    @reader.stubs(:rpc_call).returns("0x00")

    assert_raises(RuntimeError) { @reader.borrowing_usd(vault_address: "0x0000000000000000000000000000000000000abc") }
  end

  test "requires a vault address" do
    assert_raises(ArgumentError) { @reader.borrowing_usd(vault_address: "") }
  end
end
