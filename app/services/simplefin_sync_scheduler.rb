class SimplefinSyncScheduler
  JOB_NAME = "sync_simplefin"
  CRON = "17 */6 * * *"
  DESCRIPTION = "Syncs active SimpleFIN items without running the family-wide sync"

  def self.sync!
    job = Sidekiq::Cron::Job.create(
      name: JOB_NAME,
      cron: CRON,
      class: "SyncSimplefinJob",
      queue: "scheduled",
      description: DESCRIPTION
    )

    if job.nil? || (job.respond_to?(:valid?) && !job.valid?)
      error_message = job.respond_to?(:errors) ? job.errors.to_a.join(", ") : "unknown error"
      Rails.logger.error("[SimplefinSyncScheduler] Failed to create cron job: #{error_message}")
      raise StandardError, "Failed to create SimpleFIN sync schedule: #{error_message}"
    end

    Rails.logger.info("[SimplefinSyncScheduler] Created cron job with schedule: #{CRON} UTC")
    job
  end
end
