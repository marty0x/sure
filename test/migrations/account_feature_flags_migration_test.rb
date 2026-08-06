require "test_helper"
require Rails.root.join("db/migrate/20260708000001_add_exclude_from_net_worth_to_accounts")
require Rails.root.join("db/migrate/20260806133000_reconcile_account_feature_flags")

class AccountFeatureFlagsMigrationTest < ActiveSupport::TestCase
  test "exclude-from-net-worth migration is safe when the fork column already exists" do
    migration = AddExcludeFromNetWorthToAccounts.new
    migration.stubs(:column_exists?).with(:accounts, :exclude_from_net_worth).returns(true)
    migration.stubs(:index_exists?).with(:accounts, [ :family_id, :exclude_from_net_worth ]).returns(true)
    migration.expects(:add_column).never
    migration.expects(:add_index).never

    migration.migrate(:up)
  end

  test "reconciliation adds category matcher skipped by the timestamp collision" do
    migration = ReconcileAccountFeatureFlags.new
    migration.stubs(:column_exists?).with(:accounts, :enable_category_matcher).returns(false)
    migration.expects(:add_column).with(
      :accounts,
      :enable_category_matcher,
      :boolean,
      default: true,
      null: false
    )

    migration.migrate(:up)
  end
end
