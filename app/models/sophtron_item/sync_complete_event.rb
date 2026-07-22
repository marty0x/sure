class SophtronItem::SyncCompleteEvent
  attr_reader :sophtron_item

  def initialize(sophtron_item)
    @sophtron_item = sophtron_item
  end

  def broadcast
    # Update the Sophtron item view
    sophtron_item.broadcast_replace_to(
      sophtron_item.family,
      target: "sophtron_item_#{sophtron_item.id}",
      partial: "sophtron_items/sophtron_item",
      locals: { sophtron_item: sophtron_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    sophtron_item.family.broadcast_sync_complete unless sophtron_item.part_of_larger_sync?
  end
end
