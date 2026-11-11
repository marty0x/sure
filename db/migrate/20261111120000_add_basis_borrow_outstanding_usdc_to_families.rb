class AddBasisBorrowOutstandingUsdcToFamilies < ActiveRecord::Migration[8.1]
  def change
    add_column :families, :basis_borrow_outstanding_usdc, :decimal, precision: 19, scale: 6, default: 0, null: false
    add_check_constraint :families, "basis_borrow_outstanding_usdc >= 0", name: "families_basis_borrow_outstanding_usdc_nonnegative"

    # Backfill the current manual borrow for basis-configured families.
    # The Cash LendBorrowed ledger reads $0 for the configured safe (no
    # LendBorrowed events exist for it), so the outstanding is tracked
    # manually from here on. It was $448 at the time of this change.
    reversible do |dir|
      dir.up do
        execute("UPDATE families SET basis_borrow_outstanding_usdc = 448 WHERE basis_long_address IS NOT NULL AND basis_long_address <> ''")
      end
    end
  end
end
