class CspController < ApplicationController
  include BudgetOwnership

  before_action :require_preview_features!
  before_action :set_budget, only: %i[show update_buckets]

  def show
    @plan = CspPlan.new(@budget)
    @month_label = @budget.start_date.strftime("%B %Y")
    @prev_month_param = Budget.date_to_param(@budget.start_date.prev_month)
    @next_month_param = Budget.date_to_param(@budget.start_date.next_month)
    @bucket_options = Category::CSP_BUCKET_KEYS.map { |key| [ t("csp.buckets.#{key}"), key ] }

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("csp.show.title"), nil ] ]
  end

  # Bulk-assigns budget categories to Conscious Spending Plan buckets. The
  # assignment lives on Category (not the monthly row) so one save covers
  # every month, past and future.
  def update_buckets
    assignments = params[:category_buckets]&.to_unsafe_h || {}

    Category.transaction do
      assignments.each do |category_id, bucket|
        category = Current.family.categories.find(category_id)
        bucket = bucket.presence
        if bucket && !Category::CSP_BUCKET_KEYS.include?(bucket)
          raise ActionController::BadRequest, "Unknown CSP bucket: #{bucket}"
        end
        category.update!(csp_bucket: bucket)
      end
    end

    redirect_to csp_path(month_year: @budget.to_param, **budget_owner_query), notice: t(".success")
  end

  private
    def set_budget
      month_param = params[:month_year].presence || Budget.date_to_param(Date.current)
      start_date = Budget.param_to_date(month_param, family: Current.family)
      @budget = resolve_budget(start_date)
      raise ActiveRecord::RecordNotFound unless @budget
    end
end
