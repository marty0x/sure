class AddExcludeFromNetWorthToAccounts < ActiveRecord::Migration[7.2]
  def up
    unless column_exists?(:accounts, :exclude_from_net_worth)
      add_column :accounts, :exclude_from_net_worth, :boolean, default: false, null: false
    end

    unless index_exists?(:accounts, [ :family_id, :exclude_from_net_worth ])
      add_index :accounts, [ :family_id, :exclude_from_net_worth ]
    end
  end

  def down
    if index_exists?(:accounts, [ :family_id, :exclude_from_net_worth ])
      remove_index :accounts, [ :family_id, :exclude_from_net_worth ]
    end

    if column_exists?(:accounts, :exclude_from_net_worth)
      remove_column :accounts, :exclude_from_net_worth
    end
  end
end
