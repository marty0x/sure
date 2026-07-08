class AddExcludeFromNetWorthToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :exclude_from_net_worth, :boolean, default: false, null: false
    add_index :accounts, [ :family_id, :exclude_from_net_worth ]
  end
end