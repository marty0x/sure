require "json"
require "net/http"

# Reads a user's live borrow balance from the ether.fi Cash DebtManager contract
# on Optimism mainnet. ether.fi Cash lets you borrow USDC against weETH collateral
# held in your Cash safe; DebtManager#borrowingOf(address) returns the total
# outstanding debt for that safe in USD with 6 decimals.
class BasisTrade::CashLoanReader
  RPC_URL = "https://mainnet.optimism.io".freeze

  # ether.fi Cash DebtManager on Optimism (chain id 10). See
  # https://github.com/etherfi-protocol/cash-v3 -> deployments/mainnet/10/deployments.json
  DEBT_MANAGER_ADDRESS = "0x0078C5a459132e279056B2371fE8A8eC973A9553".freeze

  # keccak256("borrowingOf(address)")[0, 4]
  BORROWING_OF_SELECTOR = "186c66cc".freeze

  # DebtManager reports all USD amounts with 6 decimals.
  USD_DECIMALS = 6

  # Returns the outstanding borrow balance for the vault (safe) in USD as a BigDecimal.
  def borrowing_usd(vault_address:)
    raise ArgumentError, "vault_address is required" if vault_address.blank?

    padded_address = vault_address.to_s.delete_prefix("0x").downcase.rjust(64, "0")
    data = "0x#{BORROWING_OF_SELECTOR}#{padded_address}"
    raw = rpc_call("eth_call", [ { to: DEBT_MANAGER_ADDRESS, data: data }, "latest" ])

    decode_total_borrowings(raw)
  end

  private
    # borrowingOf(address) returns (TokenData[] memory, uint256 totalBorrowingsInUsd).
    # The ABI head is [offset_to_array (32 bytes), totalBorrowings (32 bytes)], so the
    # total we want is the second 32-byte word of the returned data.
    def decode_total_borrowings(raw)
      payload = raw.to_s.delete_prefix("0x")
      raise "Unexpected DebtManager response: #{raw.inspect}" if payload.length < 128

      total_units = payload[64, 64].to_i(16)
      BigDecimal(total_units.to_s) / (10 ** USD_DECIMALS)
    end

    def rpc_call(method, params)
      uri = URI(RPC_URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      raise "Optimism RPC request failed with status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      raise "Optimism RPC error: #{parsed['error']}" if parsed["error"].present?

      parsed.fetch("result")
    end
end
