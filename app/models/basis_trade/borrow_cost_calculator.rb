# Estimates the annualized cost of the Ether.fi Credit borrow that funds the
# strategy. Assumes an even spend across the month with the balance paid off
# in full monthly, which halves the borrow APR to an effective average rate;
# only a third of strategy capital is treated as the revolving spend subject
# to that cost.
module BasisTrade
  class BorrowCostCalculator
    BORROW_APR = 0.04
    AVERAGE_BALANCE_APR = BORROW_APR / 2
    BORROWED_FRACTION_OF_STRATEGY = 1.0 / 3

    def initialize(initial_amount:, direct_borrow_outstanding: 0)
      @initial_amount = initial_amount.to_f
      @direct_borrow_outstanding = direct_borrow_outstanding.to_f
    end

    def summary
      return nil if initial_amount <= 0

      {
        dollars: dollars,
        percent: percent
      }
    end

    private
      attr_reader :initial_amount, :direct_borrow_outstanding

      def dollars
        (revolving_borrow_cost + direct_borrow_cost).round(2)
      end

      def revolving_borrow_cost
        BORROWED_FRACTION_OF_STRATEGY * initial_amount * AVERAGE_BALANCE_APR
      end

      def direct_borrow_cost
        direct_borrow_outstanding * BORROW_APR
      end

      def percent
        ((dollars / initial_amount) * 100).round(2)
      end
  end
end
