class ReconcileAccountFeatureFlags < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:accounts, :enable_category_matcher)
      add_column :accounts, :enable_category_matcher, :boolean, default: true, null: false
    end
  end

  def down
    remove_column :accounts, :enable_category_matcher if column_exists?(:accounts, :enable_category_matcher)
  end
end
