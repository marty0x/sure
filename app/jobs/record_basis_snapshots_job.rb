class RecordBasisSnapshotsJob < ApplicationJob
  queue_as :scheduled

  def perform(recorded_at: Time.current)
    Family.find_each do |family|
      next unless family.basis_trade_sources_configured?

      BasisTrade::SnapshotRecorder.new(family: family, recorded_at: recorded_at).call
    rescue StandardError => error
      Rails.logger.error("[RecordBasisSnapshotsJob] family_id=#{family.id} error=#{error.class}: #{error.message}")
    end
  end
end
