require "test_helper"

class RecordBasisSnapshotsJobTest < ActiveJob::TestCase
  test "records snapshots for configured families" do
    configured_family = families(:dylan_family)
    unconfigured_family = families(:empty)

    configured_family.stubs(:basis_trade_sources_configured?).returns(true)
    unconfigured_family.stubs(:basis_trade_sources_configured?).returns(false)

    Family.stubs(:find_each).yields(configured_family).yields(unconfigured_family)

    recorder = mock
    recorder.expects(:call).once

    BasisTrade::SnapshotRecorder.expects(:new).with(family: configured_family, recorded_at: kind_of(ActiveSupport::TimeWithZone)).returns(recorder)
    BasisTrade::SnapshotRecorder.expects(:new).with(family: unconfigured_family, recorded_at: kind_of(ActiveSupport::TimeWithZone)).never

    updater = mock
    updater.expects(:call).once.returns(BasisTrade::CashLoanUpdater::Result.new(configured: false, updated: false))
    BasisTrade::CashLoanUpdater.expects(:new).with(family: configured_family).returns(updater)
    BasisTrade::CashLoanUpdater.expects(:new).with(family: unconfigured_family).never

    RecordBasisSnapshotsJob.perform_now
  end
end
