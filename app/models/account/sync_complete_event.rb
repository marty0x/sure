class Account::SyncCompleteEvent
  attr_reader :account

  Error = Class.new(StandardError)

  def initialize(account)
    @account = account
  end

  def broadcast
    # Replace account row in accounts list
    account.broadcast_replace_to(
      account.family,
      target: "account_#{account.id}",
      partial: "accounts/account",
      locals: { account: account }
    )

    # If this is a manual, unlinked account (i.e. not part of a Plaid Item),
    # trigger the family sync complete broadcast so net worth graph is updated.
    # Skip it if this sync is itself nested under a larger family sync (e.g. a
    # full family sync that includes this manual account) — the family sync's
    # own finalization will broadcast once on its own, so this would otherwise
    # double-fire the toast/refresh.
    if !account.linked? && !account.part_of_larger_sync?
      account.family.broadcast_sync_complete
    end

    # Refresh entire account page (only applies if currently viewing this account)
    account.broadcast_refresh
  end
end
