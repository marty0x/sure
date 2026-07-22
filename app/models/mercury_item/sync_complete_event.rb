class MercuryItem::SyncCompleteEvent
  attr_reader :mercury_item

  def initialize(mercury_item)
    @mercury_item = mercury_item
  end

  def broadcast
    # Update the Mercury item view
    mercury_item.broadcast_replace_to(
      mercury_item.family,
      target: "mercury_item_#{mercury_item.id}",
      partial: "mercury_items/mercury_item",
      locals: { mercury_item: mercury_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    mercury_item.family.broadcast_sync_complete unless mercury_item.part_of_larger_sync?
  end
end
