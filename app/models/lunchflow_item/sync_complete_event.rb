class LunchflowItem::SyncCompleteEvent
  attr_reader :lunchflow_item

  def initialize(lunchflow_item)
    @lunchflow_item = lunchflow_item
  end

  def broadcast
    # Update the Lunchflow item view
    lunchflow_item.broadcast_replace_to(
      lunchflow_item.family,
      target: "lunchflow_item_#{lunchflow_item.id}",
      partial: "lunchflow_items/lunchflow_item",
      locals: { lunchflow_item: lunchflow_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    lunchflow_item.family.broadcast_sync_complete unless lunchflow_item.part_of_larger_sync?
  end
end
