class EnableBankingItem::SyncCompleteEvent
  attr_reader :enable_banking_item

  def initialize(enable_banking_item)
    @enable_banking_item = enable_banking_item
  end

  def broadcast
    enable_banking_item.reload

    family = enable_banking_item.family
    return unless family

    # Update the Enable Banking item view on the Accounts page
    enable_banking_item.broadcast_replace_to(
      family,
      target: "enable_banking_item_#{enable_banking_item.id}",
      partial: "enable_banking_items/enable_banking_item",
      locals: { enable_banking_item: enable_banking_item }
    )

    # Update the Settings > Providers panel
    enable_banking_items = family.enable_banking_items.ordered.includes(:syncs)
    enable_banking_item.broadcast_replace_to(
      family,
      target: "enable_banking-providers-panel",
      partial: "settings/providers/enable_banking_panel",
      locals: { enable_banking_items: enable_banking_items, family: family }
    )

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    family.broadcast_sync_complete unless enable_banking_item.part_of_larger_sync?
  end
end
