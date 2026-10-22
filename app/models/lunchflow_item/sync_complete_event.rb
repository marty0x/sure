class LunchflowItem::SyncCompleteEvent
  attr_reader :lunchflow_item

  def initialize(lunchflow_item)
    @lunchflow_item = lunchflow_item
  end

  def broadcast
    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    lunchflow_item.family.broadcast_sync_complete unless lunchflow_item.part_of_larger_sync?
  end
end
