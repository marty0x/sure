class AddBasisBorrowRepaidUsdcToFamilies < ActiveRecord::Migration[8.1]
  def change
    add_column :families, :basis_borrow_repaid_usdc, :decimal, precision: 19, scale: 6, default: 0, null: false
    add_check_constraint :families, "basis_borrow_repaid_usdc >= 0", name: "families_basis_borrow_repaid_usdc_nonnegative"
  end
end
