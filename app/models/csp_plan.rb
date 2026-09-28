# Groups a month's budget actuals into Ramit Sethi's Conscious Spending Plan
# buckets, expressed as % of take-home pay (the budget's actual income).
#
# Buckets are assigned on Category#csp_bucket (subcategories inherit their
# parent's bucket), so one assignment covers every monthly budget. Only
# top-level budget categories are summed -- parent actuals already include
# their subcategories, matching IncomeStatement's own roll-up.
class CspPlan
  Bucket = Data.define(:key, :actual, :percent, :band_min, :band_max, :status, :category_count)

  def initialize(budget)
    @budget = budget
  end

  def income
    @income ||= @budget.actual_income.to_d
  end

  def buckets
    @buckets ||= Category::CSP_BUCKET_KEYS.map { |key| build_bucket(key) }
  end

  # Top-level budget categories with no bucket assignment. Shown explicitly
  # so no dollar is silently missing from the plan.
  def unassigned_budget_categories
    @unassigned_budget_categories ||= top_level_budget_categories.select do |bc|
      bc.category.csp_bucket_effective.nil?
    end
  end

  def unassigned_actual
    @unassigned_actual ||= unassigned_budget_categories.sum { |bc| bc.actual_spending.to_d }
  end

  def unassigned_percent
    percent_of_income(unassigned_actual)
  end

  def top_level_budget_categories
    @top_level_budget_categories ||=
      @budget.budget_categories.includes(:category).select { |bc| bc.category.parent_id.nil? }
  end

  private
    def build_bucket(key)
      matches = top_level_budget_categories.select { |bc| bc.category.csp_bucket_effective == key }
      actual = matches.sum { |bc| bc.actual_spending.to_d }
      percent = percent_of_income(actual)
      band = Category::CSP_BUCKETS.fetch(key)

      Bucket.new(
        key: key,
        actual: actual,
        percent: percent,
        band_min: band[:min],
        band_max: band[:max],
        status: bucket_status(percent, band, key),
        category_count: matches.count
      )
    end

    def top_level_budget_categories
      @top_level_budget_categories ||=
        @budget.budget_categories.includes(:category).select { |bc| bc.category.parent_id.nil? }
    end

    def percent_of_income(amount)
      return 0.to_d if income.zero?

      (amount / income * 100).round(1)
    end

    def bucket_status(percent, band, key)
      # Ramit's bands are directional: overspending fixed costs or guilt-free
      # is the problem; undershooting investments or savings is the problem.
      # Landing on the "good" side of an open band edge is on track.
      case key
      when "fixed_costs" then percent > band[:max] ? :above : :on_track
      when "guilt_free" then percent > band[:max] ? :above : :on_track
      when "investments" then percent < band[:min] ? :below : :on_track
      when "savings" then percent < band[:min] ? :below : :on_track
      end
    end
end
