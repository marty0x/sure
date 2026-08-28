require "test_helper"

class BasisTrade::BorrowCostCalculatorTest < ActiveSupport::TestCase
  test "computes the annualized dollar cost and percent drag from the strategy's initial amount" do
    summary = BasisTrade::BorrowCostCalculator.new(initial_amount: 9976.39).summary

    # (1/3) * 9976.39 * 0.02 = 66.51
    assert_equal 66.51, summary[:dollars]
    # 66.51 / 9976.39 * 100 = 0.67 (constant: (1/3) * 2% regardless of initial amount)
    assert_equal 0.67, summary[:percent]
  end

  test "adds the full Cash direct-borrow APR to the annualized cost" do
    summary = BasisTrade::BorrowCostCalculator.new(
      initial_amount: 10_000,
      direct_borrow_outstanding: 1_000
    ).summary

    # Existing revolving estimate: (1/3) * 10,000 * 2% = $66.67.
    # Direct Basis debt stays outstanding, so it costs 1,000 * 4% = $40.00.
    assert_equal 106.67, summary[:dollars]
    assert_equal 1.07, summary[:percent]
  end

  test "returns nil when the initial amount is zero or negative" do
    assert_nil BasisTrade::BorrowCostCalculator.new(initial_amount: 0).summary
    assert_nil BasisTrade::BorrowCostCalculator.new(initial_amount: -100).summary
  end
end
