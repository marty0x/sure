require "test_helper"

class BasisTrade::CashLoanReaderTest < ActiveSupport::TestCase
  setup do
    @reader = BasisTrade::CashLoanReader.new
  end

  test "decodes total debt in USD from Aave v4 account data" do
    # getUserAccountData returns seven uint256 words. Word 5 is totalDebtValueRay,
    # where $1 is represented by 1e26 Value units multiplied by RAY (1e27).
    total_debt = (BigDecimal("1234.56") * (10 ** BasisTrade::CashLoanReader::USD_DEBT_DECIMALS)).to_i.to_s(16).rjust(64, "0")
    response_words = Array.new(7) { "0".rjust(64, "0") }
    response_words[4] = total_debt
    @reader.stubs(:rpc_call).returns("0x#{response_words.join}")

    assert_equal BigDecimal("1234.56"), @reader.borrowing_usd(vault_address: "0x0000000000000000000000000000000000000abc")
  end

  test "calls Aave v4 Spoke getUserAccountData with the left-padded lowercased vault address" do
    vault = "0x00000000000000000000000000000000000000AA"
    expected_data = "0x#{BasisTrade::CashLoanReader::GET_USER_ACCOUNT_DATA_SELECTOR}#{'aa'.rjust(64, '0')}"

    @reader.expects(:rpc_call).with(
      "eth_call",
      [ { to: BasisTrade::CashLoanReader::SPOKE_ADDRESS, data: expected_data }, "latest" ]
    ).returns("0x#{'0'.rjust(64 * 7, '0')}")

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
