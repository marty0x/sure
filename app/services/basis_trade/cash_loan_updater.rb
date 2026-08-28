# Overwrites the manually-tracked "ether.fi Credit" loan balance with direct
# CashEventEmitter LendBorrowed USDC values less the family's cumulative Basis
# repayments, floored at zero because Basis debt cannot be negative. It intentionally excludes Ether.fi Cash facility/card debt.
#
# Runs on the same cadence as basis snapshots (see RecordBasisSnapshotsJob).
class BasisTrade::CashLoanUpdater
  LOAN_ACCOUNT_NAME = "ether.fi Credit".freeze

  Result = Struct.new(:configured, :updated, :balance, :error, keyword_init: true)

  def initialize(family:, reader: nil)
    @family = family
    @reader = reader || BasisTrade::CashLoanReader.new
  end

  def call
    return Result.new(configured: false, updated: false) if @family.basis_long_address.blank?

    account = loan_account
    # Not every configured family runs the ether.fi Cash strategy, so a missing
    # loan account is a benign skip rather than an error.
    return Result.new(configured: true, updated: false) if account.nil?

    direct_borrow_total = @reader.borrowed_usdc(vault_address: @family.basis_long_address)
    balance = [ direct_borrow_total - @family.basis_borrow_repaid_usdc, BigDecimal("0") ].max

    result = account.set_current_balance(balance)
    raise result.error if result.error.present?

    Result.new(configured: true, updated: true, balance: balance)
  rescue StandardError => error
    Result.new(configured: true, updated: false, error: error.message)
  end

  private
    def loan_account
      scope = @family.accounts.where(accountable_type: "Loan")
      scope.find_by(name: LOAN_ACCOUNT_NAME) || scope.where("name ILIKE ?", LOAN_ACCOUNT_NAME).first
    end
end
