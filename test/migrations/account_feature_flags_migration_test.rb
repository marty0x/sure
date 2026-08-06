require "test_helper"
require Rails.root.join("db/migrate/20260708000001_add_exclude_from_net_worth_to_accounts")
require Rails.root.join("db/migrate/20260806133000_reconcile_account_feature_flags")

class AccountFeatureFlagsMigrationTest < ActiveSupport::TestCase
  test "legacy fork schema upgrades through the upstream timestamp collision" do
    connection = ActiveRecord::Base.connection

    assert connection.column_exists?(:accounts, :exclude_from_net_worth)
    connection.remove_column(:accounts, :enable_category_matcher) if connection.column_exists?(:accounts, :enable_category_matcher)

    AddExcludeFromNetWorthToAccounts.new.migrate(:up)
    ReconcileAccountFeatureFlags.new.migrate(:up)

    assert connection.column_exists?(:accounts, :exclude_from_net_worth)
    assert connection.index_exists?(:accounts, [ :family_id, :exclude_from_net_worth ])
    assert connection.column_exists?(:accounts, :enable_category_matcher)
  ensure
    unless connection.column_exists?(:accounts, :enable_category_matcher)
      connection.add_column(:accounts, :enable_category_matcher, :boolean, default: true, null: false)
    end
    connection.schema_cache.clear!
  end
end
