require "test_helper"

class BasisTrade::SnapshotRecorderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "stores live basis values in snapshot units and preserves reward-basis metadata" do
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
      rewards_accrued_cents: 8_492,
      metadata: {
        rewards_basis: {
          eth_balance: BigDecimal("2.4901"),
          eth_price_usd: BigDecimal("2850.93"),
          usdc_balance: BigDecimal("84.92")
        },
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
    assert_equal 84_920, snapshot.rewards_accrued_cents
    assert_equal "USD", snapshot.currency
    assert_equal "2.4901", snapshot.metadata.dig("rewards_basis", "eth_balance").to_s
    assert_equal "2850.93", snapshot.metadata.dig("rewards_basis", "eth_price_usd").to_s
    assert_equal "84.92", snapshot.metadata.dig("rewards_basis", "usdc_balance").to_s
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
        rewards_basis: {
          eth_balance: BigDecimal("2.4901"),
          eth_price_usd: BigDecimal("2850.93"),
          usdc_balance: BigDecimal("0")
        },
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
