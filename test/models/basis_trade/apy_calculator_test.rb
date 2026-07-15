require "test_helper"

class BasisTrade::ApyCalculatorTest < ActiveSupport::TestCase
  test "computes simple-linear annualized return from first to last point" do
    points = [
      { date: "2026-06-15", recorded_at: "2026-06-15T12:00:00Z", combined: 1000.0 },
      { date: "2026-06-25", recorded_at: "2026-06-25T12:00:00Z", combined: 1010.0 }
    ]

    summary = BasisTrade::ApyCalculator.new(points: points).summary

    # (1010/1000 - 1) * (365/10) * 100 = 36.5%
    assert_equal 36.5, summary[:current]
    assert_equal Date.new(2026, 6, 15), summary[:start_date]
  end

  test "returns nil current apy when fewer than 2 points" do
    summary = BasisTrade::ApyCalculator.new(points: []).summary
    assert_nil summary[:current]
    assert_nil summary[:start_date]

    summary = BasisTrade::ApyCalculator.new(
      points: [ { date: "2026-06-15", recorded_at: "2026-06-15T12:00:00Z", combined: 1000.0 } ]
    ).summary
    assert_nil summary[:current]
  end

  test "returns nil current apy when the baseline value is zero or negative" do
    points = [
      { date: "2026-06-15", recorded_at: "2026-06-15T12:00:00Z", combined: 0.0 },
      { date: "2026-06-25", recorded_at: "2026-06-25T12:00:00Z", combined: 1010.0 }
    ]

    assert_nil BasisTrade::ApyCalculator.new(points: points).summary[:current]
  end

  test "builds a trend series using the last snapshot per day, anchored to the same baseline" do
    points = (0..8).map do |day|
      {
        date: (Date.new(2026, 7, 1) + day).iso8601,
        recorded_at: ((Date.new(2026, 7, 1) + day).to_time(:utc) + 12.hours).iso8601,
        combined: 1000.0 + (day * 10)
      }
    end

    summary = BasisTrade::ApyCalculator.new(points: points).summary
    trend = summary[:trend]

    assert_instance_of Series, trend
    # 9 days of data, one point per day; only the last 7 distinct days are kept.
    assert_equal 7, trend.values.size
    assert_equal Date.new(2026, 7, 9), trend.values.last.date
  end

  test "returns nil trend when fewer than 2 distinct days have computable apy" do
    points = [
      { date: "2026-07-01", recorded_at: "2026-07-01T12:00:00Z", combined: 1000.0 },
      { date: "2026-07-01", recorded_at: "2026-07-01T18:00:00Z", combined: 1005.0 }
    ]

    summary = BasisTrade::ApyCalculator.new(points: points).summary
    assert_nil summary[:trend]
  end
end
