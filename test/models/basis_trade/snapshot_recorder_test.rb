require "test_helper"

class BasisTrade::SnapshotRecorderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "stores live basis values in snapshot units and computes rewards from the initial stored spot value" do
    @family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
    )

    @family.basis_trade_snapshots.create!(
      recorded_at: Time.zone.parse("2026-06-20 00:00:00"),
      spot_leg_cents: 7_000_000,
      short_leg_cents: -7_000_000,
      funding_accrued_cents: 0,
      rewards_accrued_cents: 0,
      currency: "USD"
    )

    live_snapshot = {
      recorded_at: Time.zone.parse("2026-06-21 12:00:00"),
      currency: "USD",
      spot_leg_cents: 709_544,
      short_leg_cents: 711_299,
      funding_accrued_cents: 63,
      rewards_accrued_cents: 9_544,
      metadata: {
        lighter: {
          total_position_notional: BigDecimal("7112.99")
        }
      }
    }

    builder = stub(call: BasisTrade::LiveSnapshotBuilder::Result.new(configured: true, snapshot: live_snapshot))

    snapshot = BasisTrade::SnapshotRecorder.new(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-21 12:00:00"),
      live_snapshot_builder: builder
    ).call

    assert_equal 7_095_440, snapshot.spot_leg_cents
    assert_equal(-7_112_990, snapshot.short_leg_cents)
    assert_equal 630, snapshot.funding_accrued_cents
    assert_equal 95_440, snapshot.rewards_accrued_cents
    assert_equal "USD", snapshot.currency
  end

  test "uses the first recorded spot value as the anchor for the initial snapshot" do
    @family.update!(
      basis_long_address: "0x1111111111111111111111111111111111111111",
      basis_long_token_addresses: "0x2222222222222222222222222222222222222222",
      basis_lighter_address: "0x3333333333333333333333333333333333333333"
    )

    live_snapshot = {
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      currency: "USD",
      spot_leg_cents: 709_544,
      short_leg_cents: 711_299,
      funding_accrued_cents: 63,
      rewards_accrued_cents: 0,
      metadata: {
        lighter: {
          total_position_notional: BigDecimal("7112.99")
        }
      }
    }

    builder = stub(call: BasisTrade::LiveSnapshotBuilder::Result.new(configured: true, snapshot: live_snapshot))

    snapshot = BasisTrade::SnapshotRecorder.new(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      live_snapshot_builder: builder
    ).call

    assert_equal 0, snapshot.rewards_accrued_cents
    assert_equal 7_095_440, snapshot.spot_leg_cents
  end
end
