class RecordBasisSnapshotsJob < ApplicationJob
  queue_as :scheduled

  def perform(recorded_at: Time.current)
    Family.find_each do |family|
      next unless family.basis_trade_sources_configured?

      BasisTrade::SnapshotRecorder.new(family: family, recorded_at: recorded_at).call
      refresh_cash_loan(family)
    rescue StandardError => error
      Rails.logger.error("[RecordBasisSnapshotsJob] family_id=#{family.id} error=#{error.class}: #{error.message}")
    end
  end

  private
    # Pulls the live ether.fi Cash borrow balance and overwrites the manually-set
    # "ether.fi Credit" loan value. Errors are captured on the result (not raised)
    # so a debt-read failure never blocks snapshot recording for other families.
    def refresh_cash_loan(family)
      result = BasisTrade::CashLoanUpdater.new(family: family).call

      if result.error.present?
        Rails.logger.error("[RecordBasisSnapshotsJob] cash loan update failed family_id=#{family.id} error=#{result.error}")
      elsif result.updated
        Rails.logger.info("[RecordBasisSnapshotsJob] cash loan updated family_id=#{family.id} balance=#{result.balance}")
      end
    end
end
