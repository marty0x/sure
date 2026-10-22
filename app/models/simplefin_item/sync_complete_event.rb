class SimplefinItem::SyncCompleteEvent
  attr_reader :simplefin_item

  def initialize(simplefin_item)
    @simplefin_item = simplefin_item
  end

  def broadcast
    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    simplefin_item.family.broadcast_sync_complete unless simplefin_item.part_of_larger_sync?
  end
end
