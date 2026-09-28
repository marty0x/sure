class CspController < ApplicationController
  include BudgetOwnership

  before_action :require_preview_features!
  before_action :set_budget, only: %i[show update_buckets update_take_home_pay]

  def show
    @plan = CspPlan.new(@budget)
    @month_label = @budget.start_date.strftime("%B %Y")
    @prev_month_param = Budget.date_to_param(@budget.start_date.prev_month)
    @next_month_param = Budget.date_to_param(@budget.start_date.next_month)
    @bucket_options = Category::CSP_BUCKET_KEYS.map { |key| [ t("csp.buckets.#{key}"), key ] }

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("csp.show.title"), nil ] ]
  end

  # Bulk-assigns budget categories and accounts to Conscious Spending Plan
  # buckets. The assignment lives on Category/Account (not the monthly row)
  # so one save covers every month, past and future.
  def update_buckets
    category_assignments = params[:category_buckets]&.to_unsafe_h || {}
    account_assignments = params[:account_buckets]&.to_unsafe_h || {}

    ApplicationRecord.transaction do
      category_assignments.each do |category_id, bucket|
        category = Current.family.categories.find(category_id)
        category.update!(csp_bucket: validated_bucket(bucket))
      end

      account_assignments.each do |account_id, bucket|
        account = Current.family.accounts.find(account_id)
        account.update!(csp_bucket: validated_bucket(bucket))
      end
    end

    redirect_to csp_path(month_year: @budget.to_param, **budget_owner_query), notice: t(".success")
  end

  # Saves the manual take-home pay override. Stored on the family (not the
  # monthly budget) so one value covers every month. Blank clears it.
  def update_take_home_pay
    amount = params[:take_home_pay].presence
    if amount && !(amount.to_s =~ /\A\d+(\.\d{1,2})?\z/)
      redirect_to csp_path(month_year: @budget.to_param, **budget_owner_query), alert: t(".invalid") and return
    end

    Current.family.update!(csp_take_home_pay: amount)
    redirect_to csp_path(month_year: @budget.to_param, **budget_owner_query), notice: t(".success")
  end

  private
    def validated_bucket(bucket)
      bucket = bucket.presence
      if bucket && !Category::CSP_BUCKET_KEYS.include?(bucket)
        raise ActionController::BadRequest, "Unknown CSP bucket: #{bucket}"
      end
      bucket
    end

    def set_budget
      month_param = params[:month_year].presence || Budget.date_to_param(Date.current)
      start_date = Budget.param_to_date(month_param, family: Current.family)
      @budget = resolve_budget(start_date)
      raise ActiveRecord::RecordNotFound unless @budget
    end
end
