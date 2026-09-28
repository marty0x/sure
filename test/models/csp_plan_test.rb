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
end
