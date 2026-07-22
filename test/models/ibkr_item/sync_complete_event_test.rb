require "test_helper"

class IbkrItem::SyncCompleteEventTest < ActiveSupport::TestCase
  fixtures :families, :ibkr_items

  test "broadcast refreshes provider item and family stream when not nested under a larger sync" do
    ibkr_item = ibkr_items(:configured_item)
    family = ibkr_item.family

    ibkr_item.stubs(:part_of_larger_sync?).returns(false)
    ibkr_item.expects(:broadcast_replace_to).with(
      family,
      target: "ibkr_item_#{ibkr_item.id}",
      partial: "ibkr_items/ibkr_item",
      locals: { ibkr_item: ibkr_item }
    ).once
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
