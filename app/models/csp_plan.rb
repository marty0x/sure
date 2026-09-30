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
  Bucket = Data.define(:key, :actual, :percent, :band_min, :band_max, :status, :category_count, :transfer_count,
                       :basis_boost_amount, :basis_boost_percent, :basis_apy)
  TransferRow = Data.define(:account, :net)
  # Imputed monthly yield from the basis trade. Funding and rewards accrue
  # inside the position and never appear as budget transactions, so without
  # this the savings bucket understates true savings. Mirrors the Basis tab:
  # start-anchored projected APY net of borrow cost, prorated to one month,
  # applied to the latest account value on or before the viewed month's end.
  BasisYield = Data.define(:amount, :apy, :account_value)

  def initialize(budget)
    @budget = budget
  end

  def income
    @income ||= (@budget.family.csp_take_home_pay.presence || @budget.actual_income).to_d
  end

  # True when the user has set a manual take-home pay override.
  def manual_income?
    @budget.family.csp_take_home_pay.present?
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
  #   label of Contribution/Withdrawal; only ones that aren't a leg of a
  #   transfer pair are counted, so a transfer-matched pair isn't double
  #   counted against its budgeted bank-side outflow. Kinds already treated
  #   as budgeted expenses (investment_contribution, loan_payment, cc_payment)
  #   are left out for the same reason.
  #
  # Signed: Sure stores inflows as negative entry amounts and outflows as
  # positive, so the sum is negated — money into an assigned account
  # increases its bucket, money pulled back out reduces it.
  def transfer_rows
    @transfer_rows ||= begin
      nets = transfer_scope
        .where(
          "transactions.kind = 'funds_movement' OR (" \
          "transactions.investment_activity_label IN ('Contribution', 'Withdrawal') " \
          "AND transactions.kind IN ('standard', 'one_time') " \
          "AND NOT EXISTS (SELECT 1 FROM transfers WHERE transfers.inflow_transaction_id = transactions.id " \
          "OR transfers.outflow_transaction_id = transactions.id))"
        )
        .group("accounts.id")
        .sum("entries.amount")

      # Investment activity on tax-advantaged accounts (401k, IRA, HSA) is
      # invisible to the budget -- the income statement excludes these
      # accounts entirely -- so every unmatched Contribution/Withdrawal here
      # must be counted in the account net or it vanishes. The kind filter is
      # deliberately absent: the importer usually assigns investment_contribution,
      # but whatever the kind, nothing on these accounts can double count
      # against budget category actuals. Kinds already covered by the first
      # query (standard, one_time, funds_movement) are excluded to avoid
      # counting them twice.
      tax_advantaged_ids = @budget.family.tax_advantaged_account_ids
      if tax_advantaged_ids.present?
        investment_nets = transfer_scope
          .where(accounts: { id: tax_advantaged_ids })
          .where(
            "transactions.investment_activity_label IN ('Contribution', 'Withdrawal') " \
            "AND transactions.kind NOT IN ('standard', 'one_time', 'funds_movement') " \
            "AND NOT EXISTS (SELECT 1 FROM transfers WHERE transfers.inflow_transaction_id = transactions.id " \
            "OR transfers.outflow_transaction_id = transactions.id)"
          )
          .group("accounts.id")
          .sum("entries.amount")
        nets = nets.merge(investment_nets) { |_account_id, a, b| a + b }
      end

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

  # Imputed monthly yield from the basis trade, counted toward the savings
  # bucket (see BasisYield above). Nil when there is no basis history to
  # project from, the currencies don't match, or the projection isn't
  # positive -- the feature is a boost, not a drag.
  def basis_yield
    @basis_yield ||= compute_basis_yield
  end

  private
    def transfer_scope
      Transaction
        .excluding_pending
        .joins("INNER JOIN entries ON entries.entryable_id = transactions.id AND entries.entryable_type = 'Transaction'")
        .joins("INNER JOIN accounts ON accounts.id = entries.account_id")
        .where(accounts: { family_id: @budget.family_id })
        .where(entries: { date: @budget.start_date..@budget.end_date, excluded: false })
    end

    def build_bucket(key)
      matches = top_level_budget_categories.select { |bc| bc.category.csp_bucket_effective == key }
      actual = matches.sum { |bc| bc.actual_spending.to_d } + transfer_actual_for(key)
      boost = key == "savings" ? basis_yield : nil
      actual += boost.amount if boost
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
        transfer_count: transfer_count_for(key),
        basis_boost_amount: boost&.amount || 0.to_d,
        basis_boost_percent: boost ? percent_of_income(boost.amount) : 0.to_d,
        basis_apy: boost&.apy
      )
    end

    def compute_basis_yield
      family = @budget.family
      payload = BasisTradeSeriesBuilder.new(family: family, end_date: @budget.end_date).payload
      points = payload[:points]
      return nil if points.size < 2
      return nil unless payload[:currency].to_s.upcase == family.primary_currency_code.to_s.upcase

      apy_summary = BasisTrade::ApyCalculator.new(points: points).summary
      apy = apy_summary[:current]
      return nil if apy.nil?

      # Same net-of-borrow-cost adjustment as the Basis tab; the latest
      # snapshot's own metadata stands in for the live borrow reading.
      latest = BasisTradeSnapshot.for_family(family)
        .where(recorded_at: ..@budget.end_date.end_of_day).chronological.last
      direct_borrow_cents = latest&.metadata&.dig("direct_borrow_outstanding_cents") ||
        latest&.metadata&.dig(:direct_borrow_outstanding_cents)
      borrow = BasisTrade::BorrowCostCalculator.new(
        initial_amount: apy_summary[:initial_amount],
        direct_borrow_outstanding: direct_borrow_cents.to_i / 100.0
      ).summary
      apy = (apy - borrow[:percent]).round(2) if borrow

      # Production snapshots are persisted at 100x the documented
      # CENTS_PER_UNIT scale (observed 2026-09-30: the series builder
      # reports ~$1.06M combined for a ~$10.6K account, which inflated
      # the imputed yield 100x to ~$22.5K). Scale back to true dollars
      # here. Revisit if the stored snapshots are ever backfilled to
      # the documented scale.
      account_value = points.last[:combined].to_d / 100
      monthly_dollars = (account_value * apy / 100 / 12).round(2)
      return nil unless monthly_dollars.positive?

      # The plan works in integer cents like the rest of the budget actuals;
      # the series builder reports combined account value in dollars.
      BasisYield.new(amount: (monthly_dollars * 100).round, apy: apy, account_value: account_value)
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
