require "test_helper"

class IbkrItem::SyncCompleteEventTest < ActiveSupport::TestCase
  fixtures :families, :ibkr_items

  # The card itself is not re-rendered: it lists every account on the
  # connection and a broadcast has no viewer to filter for (#3630).
  test "broadcast refreshes the family stream, not the card, when not nested under a larger sync" do
    ibkr_item = ibkr_items(:configured_item)
    family = ibkr_item.family

    ibkr_item.stubs(:part_of_larger_sync?).returns(false)
    ibkr_item.expects(:broadcast_replace_to).never
    family.expects(:broadcast_sync_complete).once

    IbkrItem::SyncCompleteEvent.new(ibkr_item).broadcast
  end

  test "broadcast skips the family stream when nested under a larger sync" do
    ibkr_item = ibkr_items(:configured_item)
    family = ibkr_item.family

    ibkr_item.stubs(:part_of_larger_sync?).returns(true)
    ibkr_item.stubs(:broadcast_replace_to)
    family.expects(:broadcast_sync_complete).never

    IbkrItem::SyncCompleteEvent.new(ibkr_item).broadcast
  end
end
