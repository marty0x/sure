# Computes a simple-linear projected APY for the Basis chart's currently
# displayed range: annualizes the return from the range's first point to its
# last, then re-derives that same start-anchored APY as of each of the last
# 7 days with data, for a trend sparkline.
module BasisTrade
  class ApyCalculator
    DAYS_IN_YEAR = 365.0
    TREND_DAYS = 7

    def initialize(points:)
      @points = points.sort_by { |point| point[:recorded_at] }
    end

    def summary
      {
        current: current_apy,
        start_date: points.first && Date.parse(points.first[:date]),
        trend: trend_series
      }
    end

    private
      attr_reader :points

      def current_apy
        calculate_apy(points.first, points.last)
      end

      def trend_series
        last_per_day = points.group_by { |point| point[:date] }.values.map(&:last).last(TREND_DAYS)

        values = last_per_day.filter_map do |point|
          apy = calculate_apy(points.first, point)
          next if apy.nil?

          { date: Date.parse(point[:date]), value: apy }
        end

        return nil if values.size < 2

        Series.from_raw_values(values)
      end

      def calculate_apy(start_point, end_point)
        return nil if start_point.nil? || end_point.nil?

        start_value = start_point[:combined].to_f
        return nil if start_value <= 0

        days_elapsed = (Time.zone.parse(end_point[:recorded_at]) - Time.zone.parse(start_point[:recorded_at])) / 1.day
        return nil if days_elapsed <= 0

        end_value = end_point[:combined].to_f
        ((end_value / start_value - 1) * (DAYS_IN_YEAR / days_elapsed) * 100).round(2)
      end
  end
end
