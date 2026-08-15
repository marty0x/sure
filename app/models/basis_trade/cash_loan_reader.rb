require "json"
require "net/http"

# Reads a user's live total borrow balance from ether.fi's Cash LendGateway on
# Optimism mainnet. The gateway is the Cash app's Aave v4 display source: it
# aggregates every registered debt reserve using Cash's own price provider.
class BasisTrade::CashLoanReader
  RPC_URL = "https://mainnet.optimism.io".freeze

  # Ether.fi Cash LendGateway for the official Optimism Aave v4 deployment.
  # See etherfi-protocol/cash-v3 deployments/mainnet/10/cash-lend.json.
  LEND_GATEWAY_ADDRESS = "0x01F8cDFb1694eA8fE4ED6c38a0fD78d1188E03F4".freeze

  # keccak256("getAccountData(address)")[0, 4]
  GET_ACCOUNT_DATA_SELECTOR = "5d78650e".freeze

  # LendGateway::AccountData#debtUsd uses 6 decimals, matching the Cash app.
  USD_DEBT_DECIMALS = 6

  # Returns the outstanding borrow balance for the vault (safe) in USD as a BigDecimal.
  def borrowing_usd(vault_address:)
    raise ArgumentError, "vault_address is required" if vault_address.blank?

    validate_address!(vault_address)
    data = "0x#{GET_ACCOUNT_DATA_SELECTOR}#{encoded_address(vault_address)}"
    raw = rpc_call("eth_call", [ { to: LEND_GATEWAY_ADDRESS, data: data }, "latest" ])

    decode_total_debt(raw)
  end

  private
    # getAccountData(address) returns AccountData, whose second word is debtUsd.
    # The gateway calculates it from every registered Aave debt reserve using the
    # same 6-decimal PriceProvider conversion as the Ether.fi Cash app.
    def decode_total_debt(raw)
      payload = raw.to_s.delete_prefix("0x")
      raise "Unexpected Ether.fi LendGateway response: #{raw.inspect}" unless payload.match?(/\A[0-9a-fA-F]{320}\z/)

      debt_usd = payload[64, 64].to_i(16)
      BigDecimal(debt_usd.to_s) / (10 ** USD_DEBT_DECIMALS)
    end

    def encoded_address(address)
      address.delete_prefix("0x").downcase.rjust(64, "0")
    end

    def validate_address!(address)
      raise ArgumentError, "vault_address must be a 20-byte address" unless address.to_s.match?(/\A0x[0-9a-fA-F]{40}\z/)
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
