class EnableBankingItem::SyncCompleteEvent
  attr_reader :enable_banking_item

  def initialize(enable_banking_item)
    @enable_banking_item = enable_banking_item
  end

  def broadcast
    enable_banking_item.reload

    family = enable_banking_item.family
    return unless family

    # Neither the connection card nor the Settings > Providers panel is
    # streamed here: every family member subscribes to this stream, the card
    # lists every account on the connection, and the panel is admin-only and
    # holds the connection's credentials. The sync toast below makes each
    # browser re-fetch its own page.

    # Let family handle sync notifications (unless this is nested under a larger
    # family sync, whose own finalization will already broadcast once)
    family.broadcast_sync_complete unless enable_banking_item.part_of_larger_sync?
  end
end
