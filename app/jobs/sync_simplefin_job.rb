class SyncSimplefinJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    Rails.logger.info("Starting SimpleFIN-only sync")

    SimplefinItem.active.find_each do |item|
      item.sync_later
    rescue => e
      Rails.logger.error("Failed to sync SimpleFIN item #{item.id}: #{e.message}")
    end

    Rails.logger.info("Completed SimpleFIN-only sync")
  end
end
