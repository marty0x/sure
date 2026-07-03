require "test_helper"

class BasisTradeSeriesBuilderTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "returns an empty payload shape when there are no snapshots" do
    payload = BasisTradeSeriesBuilder.new(family: @family).payload

    assert_equal @family.primary_currency_code, payload[:currency]
    assert_equal [], payload[:points]
    assert_equal({ spot: 0.0, short: 0.0, funding: 0.0, rewards: 0.0, combined: 0.0 }, payload[:totals])
  end

  test "builds points in chronological order with account-value combined totals" do
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-21 12:00:00"),
      spot_leg_cents: 1_550_000,
      short_leg_cents: -30_000,
      funding_accrued_cents: 15_000,
      rewards_accrued_cents: 5_000,
      currency: "USD",
      metadata: {
        lighter: {
          total_account_value: "295.0"
        }
      }
    )
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      spot_leg_cents: 1_500_000,
      short_leg_cents: -25_000,
      funding_accrued_cents: 12_000,
      rewards_accrued_cents: 4_000,
      currency: "USD",
      metadata: {
        lighter: {
          total_account_value: "285.0"
        }
      }
    )

    payload = BasisTradeSeriesBuilder.new(family: @family).payload

    assert_equal [ "2026-06-20", "2026-06-21" ], payload[:points].map { |point| point[:date] }
    assert_equal 1785.0, payload[:points].first[:combined]
    assert_equal 1845.0, payload[:points].last[:combined]
    assert_equal 285.0, payload[:points].first[:lighter_account_value]
  end

  test "uses the initial snapshot for totals so the baseline account value uses stored lighter account value" do
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      spot_leg_cents: 1_500_000,
      short_leg_cents: -25_000,
      funding_accrued_cents: 12_000,
      rewards_accrued_cents: 0,
      currency: "USD",
      metadata: {
        rewards_basis: {
          eth_balance: "2.0",
          eth_price_usd: "3000.0",
          usdc_balance: "10.0"
        },
        lighter: {
          total_account_value: "280.0"
        }
      }
    )
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-21 12:00:00"),
      spot_leg_cents: 1_550_000,
      short_leg_cents: -30_000,
      funding_accrued_cents: 15_000,
      rewards_accrued_cents: 0,
      currency: "USD",
      metadata: {
        rewards_basis: {
          eth_balance: "2.03",
          eth_price_usd: "3100.0",
          usdc_balance: "5.0"
        },
        lighter: {
          total_account_value: "290.0"
        }
      }
    )

    totals = BasisTradeSeriesBuilder.new(
      family: @family,
      current_reward_reference: {
        eth_balance: "2.04",
        eth_price_usd: "3200.0",
        usdc_balance: "7.5"
      }
    ).payload[:totals]

    assert_equal({ spot: 1500.0, short: -25.0, funding: 12.0, rewards: 0.0, lighter_account_value: 280.0, combined: 1780.0 }, totals)
  end

  test "derives rewards from ETH quantity growth at current USD plus snapshot USDC without adding them again into combined account value" do
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      spot_leg_cents: 1_500_000,
      short_leg_cents: -25_000,
      funding_accrued_cents: 12_000,
      rewards_accrued_cents: 0,
      currency: "USD",
      metadata: {
        rewards_basis: {
          eth_balance: "2.0",
          eth_price_usd: "3000.0",
          usdc_balance: "0"
        },
        lighter: {
          total_account_value: "280.0"
        }
      }
    )
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-21 12:00:00"),
      spot_leg_cents: 1_550_000,
      short_leg_cents: -30_000,
      funding_accrued_cents: 15_000,
      rewards_accrued_cents: 0,
      currency: "USD",
      metadata: {
        rewards_basis: {
          eth_balance: "2.03",
          eth_price_usd: "3100.0",
          usdc_balance: "5.0"
        },
        lighter: {
          total_account_value: "290.0"
        }
      }
    )

    payload = BasisTradeSeriesBuilder.new(
      family: @family,
      current_reward_reference: {
        eth_balance: "2.04",
        eth_price_usd: "3200.0",
        usdc_balance: "7.5"
      }
    ).payload

    assert_equal 0.0, payload[:points].first[:rewards]
    assert_equal 101.0, payload[:points].last[:rewards]
    assert_equal 1780.0, payload[:points].first[:combined]
    assert_equal 1840.0, payload[:points].last[:combined]
    assert_equal({ spot: 1500.0, short: -25.0, funding: 12.0, rewards: 0.0, lighter_account_value: 280.0, combined: 1780.0 }, payload[:totals])
    assert_instance_of Float, payload[:points].last[:rewards]
    assert_instance_of Float, payload[:points].last[:combined]
  end

  test "filters payload points by date range" do
    BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-10 12:00:00"),
      spot_leg_cents: 1_400_000,
      currency: "USD"
    )
    inside = BasisTradeSnapshot.create!(
      family: @family,
      recorded_at: Time.zone.parse("2026-06-20 12:00:00"),
      spot_leg_cents: 1_500_000,
      currency: "USD"
    )

    payload = BasisTradeSeriesBuilder.new(
      family: @family,
      start_date: Date.new(2026, 6, 15),
      end_date: Date.new(2026, 6, 21)
    ).payload

    assert_equal [ inside.recorded_at.to_date.iso8601 ], payload[:points].map { |point| point[:date] }
  end
end
