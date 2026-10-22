class PlaidItem::SyncCompleteEvent
  attr_reader :plaid_item

  def initialize(plaid_item)
    @plaid_item = plaid_item
  end

  def broadcast
    plaid_item.family.broadcast_sync_complete unless plaid_item.part_of_larger_sync?
  end
end
