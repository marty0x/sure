# Broadcasts Turbo Stream updates when a Coinbase sync completes.
# Updates account views and notifies the family of sync completion.
class CoinbaseItem::SyncCompleteEvent
  attr_reader :coinbase_item

  # @param coinbase_item [CoinbaseItem] The item that completed syncing
  def initialize(coinbase_item)
    @coinbase_item = coinbase_item
  end

  # Broadcasts sync completion to update UI components.
  def broadcast
    # Update the Coinbase item view
    coinbase_item.broadcast_replace_to(
      coinbase_item.family,
      target: "coinbase_item_#{coinbase_item.id}",
      partial: "coinbase_items/coinbase_item",
      locals: { coinbase_item: coinbase_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    coinbase_item.family.broadcast_sync_complete unless coinbase_item.part_of_larger_sync?
  end
end
