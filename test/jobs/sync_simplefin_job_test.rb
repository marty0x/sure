require "test_helper"

class SyncSimplefinJobTest < ActiveJob::TestCase
  test "syncs all active SimpleFIN items without scheduling other providers" do
    simplefin_item = mock("simplefin_item")
    simplefin_item.expects(:sync_later).once

    simplefin_relation = mock("simplefin_active_relation")
    simplefin_relation.stubs(:find_each).yields(simplefin_item)

    SimplefinItem.expects(:active).returns(simplefin_relation)

    SyncSimplefinJob.perform_now
  end

  test "continues syncing other SimpleFIN items when one fails" do
    failing_item = mock("failing_simplefin_item")
    failing_item.expects(:sync_later).raises(StandardError.new("Test error"))
    failing_item.stubs(:id).returns(1)

    success_item = mock("success_simplefin_item")
    success_item.expects(:sync_later).once

    simplefin_relation = mock("simplefin_active_relation")
    simplefin_relation.stubs(:find_each).multiple_yields([ failing_item ], [ success_item ])

    SimplefinItem.expects(:active).returns(simplefin_relation)

    assert_nothing_raised do
      SyncSimplefinJob.perform_now
    end
  end
end
