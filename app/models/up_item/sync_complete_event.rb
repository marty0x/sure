class UpItem::SyncCompleteEvent
  attr_reader :up_item

  # Build the event for the given +up_item+.
  def initialize(up_item)
    @up_item = up_item
  end

  # Broadcast sync-complete Turbo updates for the item and family.
  def broadcast
    up_item.family.broadcast_sync_complete unless up_item.part_of_larger_sync?
  end
end
