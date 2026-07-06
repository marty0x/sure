require "test_helper"

class BasisTrade::CashLoanReaderTest < ActiveSupport::TestCase
  setup do
    @reader = BasisTrade::CashLoanReader.new
  end

  test "decodes total borrowings (6 decimals) from the DebtManager response" do
    # borrowingOf(address) returns (TokenData[], uint256 totalBorrowingsInUsd).
    # Word 1 = array offset (0x40), word 2 = total in USD with 6 decimals.
    # 1234.56 USD => 1_234_560_000 units.
    offset = "40".rjust(64, "0")
    total = 1_234_560_000.to_s(16).rjust(64, "0")
    @reader.stubs(:rpc_call).returns("0x#{offset}#{total}")

    assert_equal BigDecimal("1234.56"), @reader.borrowing_usd(vault_address: "0xabc")
  end

  test "calls DebtManager borrowingOf with the left-padded lowercased vault address" do
    vault = "0x00000000000000000000000000000000000000AA"
    expected_data = "0x#{BasisTrade::CashLoanReader::BORROWING_OF_SELECTOR}#{'aa'.rjust(64, '0')}"

    @reader.expects(:rpc_call).with(
      "eth_call",
      [ { to: BasisTrade::CashLoanReader::DEBT_MANAGER_ADDRESS, data: expected_data }, "latest" ]
    ).returns("0x#{'40'.rjust(64, '0')}#{'0'.rjust(64, '0')}")

    assert_equal BigDecimal("0"), @reader.borrowing_usd(vault_address: vault)
  end

  test "raises on a malformed response" do
    @reader.stubs(:rpc_call).returns("0x00")

    assert_raises(RuntimeError) { @reader.borrowing_usd(vault_address: "0xabc") }
  end

  test "requires a vault address" do
    assert_raises(ArgumentError) { @reader.borrowing_usd(vault_address: "") }
  end
end
