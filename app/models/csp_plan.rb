# Groups a month's budget actuals into Ramit Sethi's Conscious Spending Plan
# buckets, expressed as % of take-home pay (the budget's actual income).
#
# Buckets are assigned on Category#csp_bucket (subcategories inherit their
# parent's bucket), so one assignment covers every monthly budget. Only
# top-level budget categories are summed -- parent actuals already include
# their subcategories, matching IncomeStatement's own roll-up.
#
# Account-to-account transfers (kind funds_movement) are excluded from budget
# analytics, so they never appear in the category buckets above. The plan
# also totals each account's net transfers for the month, plus direct
# contributions/withdrawals that never touch another account (e.g. payroll
# 401k contributions); accounts assigned a bucket via Account#csp_bucket
# (e.g. HSA -> savings, 401k -> investments) have their net added into
# that bucket.
class CspPlan
  Bucket = Data.define(:key, :actual, :percent, :band_min, :band_max, :status, :category_count, :transfer_count)
  TransferRow = Data.define(:account, :net)

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

  # Net per account for the budget month, excluding zero-net accounts.
  #
  # Two kinds of flows are invisible to budget analytics, so accounts need an
  # explicit bucket assignment for them to appear in the plan:
  # - funds_movement transfers between accounts (excluded from budgets), and
  # - direct contributions/withdrawals that never touch another account
  #   (e.g. payroll 401k contributions). These carry an investment activity
  #   label of Contribution/Withdrawal; only unmatched ones (transfer_id NULL)
  #   are counted, so a transfer-matched pair isn't double counted against
  #   its budgeted bank-side outflow. Kinds already treated as budgeted
  #   expenses (investment_contribution, loan_payment, cc_payment) are left
  #   out for the same reason.
  #
  # Signed: Sure stores inflows as negative entry amounts and outflows as
  # positive, so the sum is negated — money into an assigned account
  # increases its bucket, money pulled back out reduces it.
  def transfer_rows
    @transfer_rows ||= begin
      nets = Transaction
        .excluding_pending
        .joins("INNER JOIN entries ON entries.entryable_id = transactions.id AND entries.entryable_type = 'Transaction'")
        .joins("INNER JOIN accounts ON accounts.id = entries.account_id")
        .where(accounts: { family_id: @budget.family_id })
        .where(entries: { date: @budget.start_date..@budget.end_date, excluded: false })
        .where(
          "transactions.kind = 'funds_movement' OR (" \
          "transactions.investment_activity_label IN ('Contribution', 'Withdrawal') " \
          "AND transactions.kind IN ('standard', 'one_time') " \
          "AND transactions.transfer_id IS NULL)"
        )
        .group("accounts.id")
        .sum("entries.amount")
      accounts = Account.where(id: nets.keys).index_by(&:id)
      nets.filter_map do |account_id, net|
        net = -net.to_d
        next if net.zero?

        TransferRow.new(account: accounts[account_id], net: net)
      end.sort_by { |row| row.account.name.downcase }
    end
  end

  # Net transfers assigned to the given bucket via Account#csp_bucket.
  def transfer_actual_for(bucket_key)
    @transfer_actuals ||= transfer_rows.group_by { |row| row.account.csp_bucket }
    @transfer_actuals.fetch(bucket_key, []).sum(&:net)
  end

  def transfer_count_for(bucket_key)
    @transfer_counts ||= transfer_rows.group_by { |row| row.account.csp_bucket }
    @transfer_counts.fetch(bucket_key, []).count
  end

  private
    def build_bucket(key)
      matches = top_level_budget_categories.select { |bc| bc.category.csp_bucket_effective == key }
      actual = matches.sum { |bc| bc.actual_spending.to_d } + transfer_actual_for(key)
      percent = percent_of_income(actual)
      band = Category::CSP_BUCKETS.fetch(key)

      Bucket.new(
        key: key,
        actual: actual,
        percent: percent,
        band_min: band[:min],
        band_max: band[:max],
        status: bucket_status(percent, band, key),
        category_count: matches.count,
        transfer_count: transfer_count_for(key)
      )
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
