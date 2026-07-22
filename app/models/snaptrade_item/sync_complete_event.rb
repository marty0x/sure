class SnaptradeItem::SyncCompleteEvent
  attr_reader :snaptrade_item

  def initialize(snaptrade_item)
    @snaptrade_item = snaptrade_item
  end

  def broadcast
    # Update the SnapTrade item view
    snaptrade_item.broadcast_replace_to(
      snaptrade_item.family,
      target: "snaptrade_item_#{snaptrade_item.id}",
      partial: "snaptrade_items/snaptrade_item",
      locals: { snaptrade_item: snaptrade_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    snaptrade_item.family.broadcast_sync_complete unless snaptrade_item.part_of_larger_sync?
  end
end
