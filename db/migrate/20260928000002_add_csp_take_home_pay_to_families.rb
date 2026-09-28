class AddCspTakeHomePayToFamilies < ActiveRecord::Migration[8.0]
  def change
    add_column :families, :csp_take_home_pay, :decimal, precision: 14, scale: 2
  end
end
