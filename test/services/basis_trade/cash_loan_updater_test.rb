require "test_helper"

class BasisTrade::CashLoanUpdaterTest < ActiveSupport::TestCase
  VAULT_ADDRESS = "0x1111111111111111111111111111111111111111".freeze

  setup do
    @family = families(:dylan_family)
    @family.update!(basis_long_address: VAULT_ADDRESS)
    @account = accounts(:loan)
    @account.update!(name: BasisTrade::CashLoanUpdater::LOAN_ACCOUNT_NAME)
  end

  test "overwrites the ether.fi Credit balance with the live borrow amount" do
    reader = mock
    reader.expects(:borrowing_usd).with(vault_address: @family.basis_long_address).returns(BigDecimal("7500.25"))

    result = BasisTrade::CashLoanUpdater.new(family: @family, reader: reader).call

    assert result.updated
    assert_equal BigDecimal("7500.25"), result.balance
    assert_equal BigDecimal("7500.25"), @account.reload.balance
  end

  test "skips when no vault address is configured" do
    @family.update!(basis_long_address: nil)
    reader = mock
    reader.expects(:borrowing_usd).never

    result = BasisTrade::CashLoanUpdater.new(family: @family, reader: reader).call

    assert_not result.configured
    assert_not result.updated
  end

  test "skips (no error) when the ether.fi Credit account is absent" do
    @account.update!(name: "Some Other Loan")
    reader = mock
    reader.expects(:borrowing_usd).never

    result = BasisTrade::CashLoanUpdater.new(family: @family, reader: reader).call

    assert result.configured
    assert_not result.updated
    assert_nil result.error
  end

  test "captures a read error without raising" do
    reader = mock
    reader.expects(:borrowing_usd).raises(StandardError, "RPC down")

    result = BasisTrade::CashLoanUpdater.new(family: @family, reader: reader).call

    assert_not result.updated
    assert_equal "RPC down", result.error
  end
end
