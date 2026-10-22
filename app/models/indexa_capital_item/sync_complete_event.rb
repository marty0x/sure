class IndexaCapitalItem::SyncCompleteEvent
  attr_reader :indexa_capital_item

  def initialize(indexa_capital_item)
    @indexa_capital_item = indexa_capital_item
  end

  def broadcast

    indexa_capital_item.family.broadcast_sync_complete unless indexa_capital_item.part_of_larger_sync?
  end
end
