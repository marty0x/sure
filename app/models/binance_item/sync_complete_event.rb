# frozen_string_literal: true

# Broadcasts Turbo Stream updates when a Binance sync completes.
# Updates account views and notifies the family of sync completion.
class BinanceItem::SyncCompleteEvent
  attr_reader :binance_item

  # @param binance_item [BinanceItem] The item that completed syncing
  def initialize(binance_item)
    @binance_item = binance_item
  end

  # Broadcasts sync completion to update UI components.
  def broadcast
    # Update the Binance item view
    binance_item.broadcast_replace_to(
      binance_item.family,
      target: "binance_item_#{binance_item.id}",
      partial: "binance_items/binance_item",
      locals: { binance_item: binance_item }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    binance_item.family.broadcast_sync_complete unless binance_item.part_of_larger_sync?
  end
end
