# Broadcasts Turbo Stream updates when a CoinStats sync completes.
# Updates account views and notifies the family of sync completion.
class CoinstatsItem::SyncCompleteEvent
  attr_reader :coinstats_item

  # @param coinstats_item [CoinstatsItem] The item that completed syncing
  def initialize(coinstats_item)
    @coinstats_item = coinstats_item
  end

  # Broadcasts sync completion to update UI components.
  def broadcast

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    coinstats_item.family.broadcast_sync_complete unless coinstats_item.part_of_larger_sync?
  end
end
