require "test_helper"

class CspPlanTest < ActiveSupport::TestCase
  def setup
    # Fresh family per test: fixture families carry seeded categories and
    # entries (e.g. a -100 transfer that reads as income) which would leak
    # into the plan's family-wide totals.
    @family = Family.create!
    @account = @family.accounts.create!(
      name: "Checking",
      balance: 0,
      currency: "USD",
      accountable: Depository.new
    )
    @budget = Budget.find_or_bootstrap(@family, start_date: Date.current.beginning_of_month)
  end

  test "groups budget actuals into buckets as percent of take-home pay" do
    rent = create_category!("Rent", csp_bucket: "fixed_costs")
    fun = create_category!("Fun", csp_bucket: "guilt_free")
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories

    create_entry!(category: paycheck, amount: -4000)
    create_entry!(category: rent, amount: 2000)
    create_entry!(category: fun, amount: 500)

    plan = CspPlan.new(@budget.reload)

    assert_equal 4000, plan.income

    fixed = plan.buckets.find { |b| b.key == "fixed_costs" }
    assert_equal 2000, fixed.actual
    assert_equal 50.0, fixed.percent
    assert_equal :on_track, fixed.status

    guilt = plan.buckets.find { |b| b.key == "guilt_free" }
    assert_equal 500, guilt.actual
    assert_equal 12.5, guilt.percent
    assert_equal :on_track, guilt.status

    investments = plan.buckets.find { |b| b.key == "investments" }
    assert_equal 0, investments.actual
    assert_equal :below, investments.status

    savings = plan.buckets.find { |b| b.key == "savings" }
    assert_equal :below, savings.status
  end

  test "over-target fixed costs and guilt-free spending are flagged" do
    rent = create_category!("Rent", csp_bucket: "fixed_costs")
    fun = create_category!("Fun", csp_bucket: "guilt_free")
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories

    create_entry!(category: paycheck, amount: -4000)
    create_entry!(category: rent, amount: 2800) # 70% > 60% max
    create_entry!(category: fun, amount: 1600)  # 40% > 35% max

    plan = CspPlan.new(@budget.reload)

    assert_equal :above, plan.buckets.find { |b| b.key == "fixed_costs" }.status
    assert_equal :above, plan.buckets.find { |b| b.key == "guilt_free" }.status
  end

  test "subcategories inherit their parent's bucket" do
    housing = create_category!("Housing", csp_bucket: "fixed_costs")
    maintenance = create_category!("Maintenance", parent: housing)
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories

    create_entry!(category: paycheck, amount: -2000)
    create_entry!(category: maintenance, amount: 400)

    plan = CspPlan.new(@budget.reload)

    # Parent actuals roll up subcategory spending (matches IncomeStatement),
    # so the bucket picks it up once via the top-level parent.
    fixed = plan.buckets.find { |b| b.key == "fixed_costs" }
    assert_equal 400, fixed.actual
    assert_equal :on_track, fixed.status
  end

  test "subcategory with its own bucket overrides the parent" do
    housing = create_category!("Housing", csp_bucket: "fixed_costs")
    side_hustle = create_category!("Side Hustle", parent: housing, csp_bucket: "investments")

    assert_equal "fixed_costs", housing.csp_bucket_effective
    assert_equal "investments", side_hustle.csp_bucket_effective
  end

  test "unassigned categories are reported instead of silently dropped" do
    rent = create_category!("Rent", csp_bucket: "fixed_costs")
    mystery = create_category!("Mystery")
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories

    create_entry!(category: paycheck, amount: -2000)
    create_entry!(category: rent, amount: 1000)
    create_entry!(category: mystery, amount: 300)

    plan = CspPlan.new(@budget.reload)

    assert_equal [ mystery.name, paycheck.name ].sort, plan.unassigned_budget_categories.map { |bc| bc.category.name }.sort
    assert_equal 300, plan.unassigned_actual
    assert_equal 15.0, plan.unassigned_percent
  end

  test "zero income does not divide by zero" do
    rent = create_category!("Rent", csp_bucket: "fixed_costs")
    @budget.sync_budget_categories
    create_entry!(category: rent, amount: 100)

    plan = CspPlan.new(@budget.reload)

    assert_equal 0, plan.income
    assert_equal 0, plan.buckets.find { |b| b.key == "fixed_costs" }.percent
  end

  test "nets funds_movement transfers by account and rolls assigned nets into buckets" do
    hsa = @family.accounts.create!(name: "HSA", balance: 0, currency: "USD", accountable: Depository.new, csp_bucket: "savings")
    k401 = @family.accounts.create!(name: "401k", balance: 0, currency: "USD", accountable: Depository.new, csp_bucket: "investments")
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories
    create_entry!(category: paycheck, amount: -4000)

    create_transfer!(account: hsa, amount: -300) # inbound: negative entry amount
    create_transfer!(account: k401, amount: -500)
    create_transfer!(account: @account, amount: 800) # funding side, unassigned

    plan = CspPlan.new(@budget.reload)

    assert_equal({ "HSA" => 300, "401k" => 500, "Checking" => -800 },
      plan.transfer_rows.to_h { |row| [ row.account.name, row.net ] })

    savings = plan.buckets.find { |b| b.key == "savings" }
    assert_equal 300, savings.actual
    assert_equal 1, savings.transfer_count

    investments = plan.buckets.find { |b| b.key == "investments" }
    assert_equal 500, investments.actual
    assert_equal :on_track, investments.status
  end

  test "transfer rows exclude zero-net accounts, other kinds, and other months" do
    hsa = @family.accounts.create!(name: "HSA", balance: 0, currency: "USD", accountable: Depository.new)

    # In and back out: nets to zero (inbound negative, outbound positive)
    create_transfer!(account: hsa, amount: -300)
    create_transfer!(account: hsa, amount: 300)
    # Standard transactions are budget analytics, never transfers
    Entry.create!(
      account: hsa,
      entryable: Transaction.create!(kind: "standard"),
      date: Date.current,
      name: "CSP test entry",
      amount: 999,
      currency: "USD"
    )
    # Last month's transfer belongs to last month's plan
    create_transfer!(account: hsa, amount: 111, date: Date.current.prev_month)

    plan = CspPlan.new(@budget.reload)

    assert_empty plan.transfer_rows
  end

  test "outflows from an assigned account reduce its bucket" do
    hsa = @family.accounts.create!(name: "HSA", balance: 0, currency: "USD", accountable: Depository.new, csp_bucket: "savings")
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories
    create_entry!(category: paycheck, amount: -4000)

    create_transfer!(account: hsa, amount: -500)
    create_transfer!(account: hsa, amount: 200) # pulled back to checking

    plan = CspPlan.new(@budget.reload)

    assert_equal 300, plan.buckets.find { |b| b.key == "savings" }.actual
  end

  test "includes unmatched direct contributions to assigned accounts" do
    # Payroll 401k contribution: never touches another account, so it has no
    # transfer pair. The importer auto-assigns kind investment_contribution
    # with a Contribution activity label; on a tax-advantaged account the
    # budget excludes it, so the plan must count it here.
    k401 = @family.accounts.create!(
      name: "401k", balance: 0, currency: "USD",
      accountable: Investment.new(subtype: "401k"), csp_bucket: "investments"
    )
    paycheck = create_category!("Paycheck")

    @budget.sync_budget_categories
    create_entry!(category: paycheck, amount: -4000)

    Entry.create!(
      account: k401,
      entryable: Transaction.create!(kind: "investment_contribution", investment_activity_label: "Contribution"),
      date: Date.current,
      name: "Contribution - contribution",
      amount: -1002.11, # inbound: negative entry amount
      currency: "USD"
    )

    plan = CspPlan.new(@budget.reload)

    assert_equal({ "401k" => 1002.11 },
      plan.transfer_rows.to_h { |row| [ row.account.name, row.net ] })

    investments = plan.buckets.find { |b| b.key == "investments" }
    assert_equal 1002.11, investments.actual
    assert_equal 1, investments.transfer_count
  end

  test "excludes transfer-matched contributions from transfer rows" do
    # Bank -> brokerage contribution matched as a transfer pair: the bank-side
    # outflow is the budgeted side, so the account side must not double count.
    k401 = @family.accounts.create!(name: "401k", balance: 0, currency: "USD", accountable: Depository.new, csp_bucket: "investments")

    outflow_tx = Transaction.create!(kind: "funds_movement")
    Entry.create!(account: @account, entryable: outflow_tx, date: Date.current,
      name: "Brokerage contribution", amount: 500, currency: "USD")

    inflow_tx = Transaction.create!(kind: "standard", investment_activity_label: "Contribution")
    Entry.create!(account: k401, entryable: inflow_tx, date: Date.current,
      name: "Contribution - contribution", amount: -500, currency: "USD")

    Transfer.create!(inflow_transaction: inflow_tx, outflow_transaction: outflow_tx, status: "confirmed")

    plan = CspPlan.new(@budget.reload)

    # The checking outflow is funds_movement (unassigned account: shown but
    # bucketless); the matched 401k inflow is excluded entirely.
    assert_equal({ "Checking" => -500 },
      plan.transfer_rows.to_h { |row| [ row.account.name, row.net ] })
    assert_equal 0, plan.buckets.find { |b| b.key == "investments" }.actual
  end

  test "excludes budgeted investment_contribution transactions from transfer rows" do
    # On a taxable account, properly classified contributions are already
    # budget spending via their category; counting them in the account net
    # too would double count.
    brokerage = @family.accounts.create!(
      name: "Brokerage", balance: 0, currency: "USD",
      accountable: Investment.new(subtype: "brokerage"), csp_bucket: "investments"
    )

    Entry.create!(
      account: brokerage,
      entryable: Transaction.create!(kind: "investment_contribution", investment_activity_label: "Contribution"),
      date: Date.current,
      name: "Contribution - contribution",
      amount: -500,
      currency: "USD"
    )

    plan = CspPlan.new(@budget.reload)

    assert_empty plan.transfer_rows
  end

  test "includes standard-kind unmatched contributions to assigned accounts" do
    # Manually entered (non-imported) direct contributions keep kind standard.
    k401 = @family.accounts.create!(
      name: "401k", balance: 0, currency: "USD",
      accountable: Investment.new(subtype: "401k"), csp_bucket: "investments"
    )

    Entry.create!(
      account: k401,
      entryable: Transaction.create!(kind: "standard", investment_activity_label: "Contribution"),
      date: Date.current,
      name: "Contribution - contribution",
      amount: -250,
      currency: "USD"
    )

    plan = CspPlan.new(@budget.reload)

    assert_equal({ "401k" => 250 },
      plan.transfer_rows.to_h { |row| [ row.account.name, row.net ] })
  end

  test "includes tax-advantaged contributions regardless of transaction kind" do
    # The budget excludes tax-advantaged accounts entirely, so no kind of
    # Contribution/Withdrawal there can double count -- the plan must pick
    # them up whatever kind the importer assigned.
    k401 = @family.accounts.create!(
      name: "401k", balance: 0, currency: "USD",
      accountable: Investment.new(subtype: "401k"), csp_bucket: "investments"
    )

    Entry.create!(
      account: k401,
      entryable: Transaction.create!(kind: "other", investment_activity_label: "Withdrawal"),
      date: Date.current,
      name: "Withdrawal - withdrawal",
      amount: 100,
      currency: "USD"
    )

    plan = CspPlan.new(@budget.reload)

    assert_equal({ "401k" => -100 },
      plan.transfer_rows.to_h { |row| [ row.account.name, row.net ] })
  end

  private
    def create_category!(name, parent: nil, csp_bucket: nil)
      Category.create!(
        name: "#{name} #{Time.now.to_f}",
        family: @family,
        color: "#e74c3c",
        lucide_icon: "shapes",
        parent: parent,
        csp_bucket: csp_bucket
      )
    end

    def create_entry!(category:, amount:)
      Entry.create!(
        account: @account,
        entryable: Transaction.create!(category: category),
        date: Date.current,
        name: "CSP test entry",
        amount: amount,
        currency: "USD"
      )
    end

    def create_transfer!(account:, amount:, date: Date.current)
      Entry.create!(
        account: account,
        entryable: Transaction.create!(kind: "funds_movement"),
        date: date,
        name: "CSP test transfer",
        amount: amount,
        currency: "USD"
      )
    end
end
