class IbkrItem::SyncCompleteEvent
  attr_reader :ibkr_item

  def initialize(ibkr_item)
    @ibkr_item = ibkr_item
  end

  def broadcast

    ibkr_item.family.broadcast_sync_complete unless ibkr_item.part_of_larger_sync?
  end
end
