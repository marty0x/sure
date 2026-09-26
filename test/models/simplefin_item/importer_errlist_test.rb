require "test_helper"

# Covers protocol-v2 `errlist` handling in the SimpleFIN importer.
#
# Background: when a bank session behind the SimpleFIN bridge expires, the
# bridge keeps returning HTTP 200 with its last cached snapshot and reports
# the auth failure ONLY in the v2 `errlist` array (v1 `errors` is deprecated).
# The importer must inspect `errlist` on every sync or days-stale data looks
# like a healthy sync.
class SimplefinItem::ImporterErrlistTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = SimplefinItem.create!(
      family: @family,
      name: "SF Conn",
      access_url: "https://example.com/access"
    )
    @sync = Sync.create!(syncable: @item)
    @importer = SimplefinItem::Importer.new(@item, simplefin_provider: mock(), sync: @sync)
  end

  test "record_errors extracts v2 msg instead of rendering a raw hash" do
    @importer.send(:record_errors, [
      { code: "con.auth", msg: "Authentication required for Chase", conn_id: "abc123" }
    ])

    errors = @sync.reload.sync_stats["errors"]
    assert_equal 1, errors.size
    assert_includes errors.first["message"], "Authentication required for Chase"
    refute_includes errors.first["message"], "code"
  end

  test "record_errors categorizes v2 auth entries and appends bridge guidance" do
    @importer.send(:record_errors, [
      { code: "con.auth", msg: "Authentication required for Chase", conn_id: "abc123" }
    ])

    stats = @sync.reload.sync_stats
    assert_equal 1, stats.dig("error_buckets", "auth").to_i
    assert_includes stats["errors"].first["message"], "SimpleFIN bridge"
  end

  test "record_errors with v2 auth entry does NOT flip item to requires_update" do
    assert_equal "good", @item.status

    @importer.send(:record_errors, [
      { code: "gen.auth", msg: "Reauthentication needed", conn_id: "abc123" }
    ])

    assert_equal "good", @item.reload.status,
      "per-connection errlist auth errors must not poison the whole item"
  end

  test "handle_errors with v2 con.auth flips item to requires_update" do
    assert_equal "good", @item.status

    assert_raises(Provider::Simplefin::SimplefinError) do
      @importer.send(:handle_errors, [
        { code: "con.auth", msg: "Authentication required for Chase", conn_id: "abc123" }
      ])
    end

    assert_equal "requires_update", @item.reload.status
  end

  test "handle_errors with v2 gen.auth flips item to requires_update" do
    assert_raises(Provider::Simplefin::SimplefinError) do
      @importer.send(:handle_errors, [
        { code: "gen.auth", msg: "Reauthentication needed", conn_id: "abc123" }
      ])
    end

    assert_equal "requires_update", @item.reload.status
  end

  test "fetch_accounts_data records errlist on partial responses and keeps accounts" do
    provider = mock()
    provider.expects(:get_accounts).returns(
      accounts: [ { id: "acct-1", name: "Checking" } ],
      errlist: [ { code: "con.auth", msg: "Authentication required for Chase", conn_id: "abc123" } ]
    )
    importer = SimplefinItem::Importer.new(@item, simplefin_provider: provider, sync: @sync)

    result = importer.send(:fetch_accounts_data, start_date: 30.days.ago)

    assert_equal [ { id: "acct-1", name: "Checking" } ], result[:accounts]
    assert_equal 1, @sync.reload.sync_stats.dig("error_buckets", "auth").to_i
    assert_equal "good", @item.reload.status
  end

  test "fetch_accounts_data treats errlist as fatal when no accounts are returned" do
    provider = mock()
    provider.expects(:get_accounts).returns(
      accounts: [],
      errlist: [ { code: "con.auth", msg: "Authentication required for Chase", conn_id: "abc123" } ]
    )
    importer = SimplefinItem::Importer.new(@item, simplefin_provider: provider, sync: @sync)

    assert_raises(Provider::Simplefin::SimplefinError) do
      importer.send(:fetch_accounts_data, start_date: 30.days.ago)
    end

    assert_equal "requires_update", @item.reload.status
  end
end
