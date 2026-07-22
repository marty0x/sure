class SimplefinItem::SyncCompleteEvent
  attr_reader :simplefin_item

  def initialize(simplefin_item)
    @simplefin_item = simplefin_item
  end

  def broadcast
    # Update the SimpleFin item view
    simplefin_item.broadcast_replace_to(
      simplefin_item.family,
      target: "simplefin_item_#{simplefin_item.id}",
      partial: "simplefin_items/simplefin_item",
      locals: { simplefin_item: simplefin_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    simplefin_item.family.broadcast_sync_complete unless simplefin_item.part_of_larger_sync?
  end
end
