class SnaptradeItem::SyncCompleteEvent
  attr_reader :snaptrade_item

  def initialize(snaptrade_item)
    @snaptrade_item = snaptrade_item
  end

  def broadcast

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    snaptrade_item.family.broadcast_sync_complete unless snaptrade_item.part_of_larger_sync?
  end
end
