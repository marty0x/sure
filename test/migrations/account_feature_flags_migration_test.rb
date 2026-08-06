require "test_helper"

class AccountFeatureFlagsMigrationTest < ActiveSupport::TestCase
  LEGACY_VERSION = "20260708000000"
  REPAIR_VERSIONS = %w[20260708000001 20260806133000].freeze

  test "Rails migrator upgrades the legacy production ledger through the timestamp collision" do
    connection = ActiveRecord::Base.connection
    pool = ActiveRecord::Base.connection_pool
    versions = ([ LEGACY_VERSION ] + REPAIR_VERSIONS).map { |version| connection.quote(version) }.join(", ")
    original_versions = connection.select_values("SELECT version FROM schema_migrations WHERE version IN (#{versions})")

    connection.remove_column(:accounts, :enable_category_matcher) if connection.column_exists?(:accounts, :enable_category_matcher)
    connection.execute("DELETE FROM schema_migrations WHERE version IN (#{versions})")
    connection.execute("INSERT INTO schema_migrations (version) VALUES (#{connection.quote(LEGACY_VERSION)})")
    connection.schema_cache.clear!

    migration_context = ActiveRecord::MigrationContext.new(
      Rails.application.config.paths["db/migrate"].to_a,
      pool.schema_migration,
      pool.internal_metadata
    )
    migration_context.up(20260806133000)

    assert connection.column_exists?(:accounts, :exclude_from_net_worth)
    assert connection.index_exists?(:accounts, [ :family_id, :exclude_from_net_worth ])
    assert connection.column_exists?(:accounts, :enable_category_matcher)
    assert_equal REPAIR_VERSIONS, connection.select_values(
      "SELECT version FROM schema_migrations WHERE version IN (#{REPAIR_VERSIONS.map { |version| connection.quote(version) }.join(", ")}) ORDER BY version"
    )
  ensure
    if connection
      connection.add_column(:accounts, :enable_category_matcher, :boolean, default: true, null: false) unless connection.column_exists?(:accounts, :enable_category_matcher)
      connection.execute("DELETE FROM schema_migrations WHERE version IN (#{versions})") if versions
      original_versions&.each do |version|
        connection.execute("INSERT INTO schema_migrations (version) VALUES (#{connection.quote(version)})")
      end
      connection.schema_cache.clear!
    end
  end
end
