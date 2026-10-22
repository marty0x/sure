class AkahuItem::SyncCompleteEvent
  attr_reader :akahu_item

  def initialize(akahu_item)
    @akahu_item = akahu_item
  end

  def broadcast
    akahu_item.family.broadcast_sync_complete unless akahu_item.part_of_larger_sync?
  end
end
