require "test_helper"

class SimplefinSyncSchedulerTest < ActiveSupport::TestCase
  test "creates the SimpleFIN-only cron job every six hours" do
    cron_job = mock("simplefin_cron_job")
    cron_job.stubs(:valid?).returns(true)

    Sidekiq::Cron::Job.expects(:create).with(
      name: "sync_simplefin",
      cron: "17 */6 * * *",
      class: "SyncSimplefinJob",
      queue: "scheduled",
      description: "Syncs active SimpleFIN items without running the family-wide sync"
    ).returns(cron_job)

    assert_equal cron_job, SimplefinSyncScheduler.sync!
  end

  test "raises when the SimpleFIN cron job cannot be created" do
    cron_job = mock("invalid_simplefin_cron_job")
    cron_job.stubs(:valid?).returns(false)
    cron_job.stubs(:errors).returns([ "invalid cron" ])
    Sidekiq::Cron::Job.stubs(:create).returns(cron_job)

    error = assert_raises(StandardError) { SimplefinSyncScheduler.sync! }

    assert_equal "Failed to create SimpleFIN sync schedule: invalid cron", error.message
  end
end
