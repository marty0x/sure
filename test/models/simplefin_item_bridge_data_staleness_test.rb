require "test_helper"

# Covers bridge-data-age detection in SimplefinItem#stale_sync_status.
#
# Background: when a bank session behind the SimpleFIN bridge expires, the
# bridge keeps returning HTTP 200 with its last cached snapshot, so the
# app's own syncs keep "succeeding" while the data ages. The bridge's
# per-account `balance-date` is the bank-data timestamp — a healthy bridge
# refreshes it roughly daily — so it is the signal for this condition.
class SimplefinItemBridgeDataStalenessTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = SimplefinItem.create!(
      family: @family,
      name: "SF Conn",
      access_url: "https://example.com/access",
      last_synced_at: 1.hour.ago
    )
  end

  test "flags stale when bridge bank data is older than two days despite a fresh app sync" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      Sync.create!(syncable: @item, status: "completed", completed_at: 1.hour.ago)
      @item.simplefin_accounts.create!(
        name: "Checking",
        account_id: "acct-1",
        currency: "USD",
        account_type: "checking",
        balance_date: 5.days.ago
      )

      status = @item.reload.stale_sync_status

      assert status[:stale]
      assert_equal 5, status[:days_since_bridge_data]
      assert_equal [ "Checking" ], status[:stale_bridge_account_names]
      assert_equal "Bank data for Checking is 5 days old. Check your SimpleFIN bridge — the bank connection may need re-authentication, or the bridge may not have refreshed it yet.",
                   status[:message]
      assert @item.needs_attention?, "stale bridge data should require attention"
    end
  end

  test "not stale when bridge bank data is fresh" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      Sync.create!(syncable: @item, status: "completed", completed_at: 1.hour.ago)
      @item.simplefin_accounts.create!(
        name: "Checking",
        account_id: "acct-1",
        currency: "USD",
        account_type: "checking",
        balance_date: 1.day.ago
      )

      refute @item.reload.stale_sync_status[:stale]
    end
  end

  test "not stale when no bridge balance dates are recorded yet" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      Sync.create!(syncable: @item, status: "completed", completed_at: 1.hour.ago)
      @item.simplefin_accounts.create!(
        name: "Checking",
        account_id: "acct-1",
        currency: "USD",
        account_type: "checking"
      )

      refute @item.reload.stale_sync_status[:stale]
    end
  end

  test "flags the stale account even when other accounts on the item are fresh" do
    travel_to Time.zone.local(2026, 9, 26, 12) do
      Sync.create!(syncable: @item, status: "completed", completed_at: 1.hour.ago)
      @item.simplefin_accounts.create!(
        name: "Stale checking",
        account_id: "acct-1",
        currency: "USD",
        account_type: "checking",
        balance_date: 10.days.ago
      )
      @item.simplefin_accounts.create!(
        name: "Fresh savings",
        account_id: "acct-2",
        currency: "USD",
        account_type: "checking",
        balance_date: 1.day.ago
      )

      status = @item.reload.stale_sync_status

      assert status[:stale], "one stale institution must not hide behind fresh ones"
      assert_equal 10, status[:days_since_bridge_data]
      assert_equal [ "Stale checking" ], status[:stale_bridge_account_names]
      assert_includes status[:message], "Stale checking"
      refute_includes status[:message], "Fresh savings"
    end
  end
end
