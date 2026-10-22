class MercuryItem::SyncCompleteEvent
  attr_reader :mercury_item

  def initialize(mercury_item)
    @mercury_item = mercury_item
  end

  def broadcast
    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    mercury_item.family.broadcast_sync_complete unless mercury_item.part_of_larger_sync?
  end
end
