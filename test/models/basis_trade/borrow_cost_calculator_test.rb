require "test_helper"

class BasisTrade::BorrowCostCalculatorTest < ActiveSupport::TestCase
  test "computes the annualized dollar cost and percent drag from the strategy's initial amount" do
    summary = BasisTrade::BorrowCostCalculator.new(initial_amount: 9976.39).summary

    # (1/3) * 9976.39 * 0.02 = 66.51
    assert_equal 66.51, summary[:dollars]
    # 66.51 / 9976.39 * 100 = 0.67 (constant: (1/3) * 2% regardless of initial amount)
    assert_equal 0.67, summary[:percent]
  end

  test "returns nil when the initial amount is zero or negative" do
    assert_nil BasisTrade::BorrowCostCalculator.new(initial_amount: 0).summary
    assert_nil BasisTrade::BorrowCostCalculator.new(initial_amount: -100).summary
  end
end
