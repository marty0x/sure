require "json"
require "net/http"

# Reads a user's live total borrow balance from ether.fi's Aave v4 Spoke on
# Optimism mainnet. The Spoke records the Cash Safe's position, including
# accrued interest across every borrowed asset.
class BasisTrade::CashLoanReader
  RPC_URL = "https://mainnet.optimism.io".freeze

  # ether.fi's official Optimism Aave v4 Spoke. See:
  # https://etherfi.gitbook.io/etherfi/products/borrow/lending-market-parameters
  SPOKE_ADDRESS = "0xdffcC3536D932eb51Df51a7F5FA407c4270d5308".freeze

  # keccak256("getUserAccountData(address)")[0, 4]
  GET_USER_ACCOUNT_DATA_SELECTOR = "bf92857c".freeze

  # Aave v4 Value uses 26 decimals per USD and totalDebtValueRay adds RAY's
  # 27 decimals. See etherfi-protocol/aave-v4 SpokeUtils#toValue.
  USD_DEBT_DECIMALS = 53

  # Returns the outstanding borrow balance for the vault (safe) in USD as a BigDecimal.
  def borrowing_usd(vault_address:)
    raise ArgumentError, "vault_address is required" if vault_address.blank?

    validate_address!(vault_address)
    data = "0x#{GET_USER_ACCOUNT_DATA_SELECTOR}#{encoded_address(vault_address)}"
    raw = rpc_call("eth_call", [ { to: SPOKE_ADDRESS, data: data }, "latest" ])

    decode_total_debt(raw)
  end

  private
    # getUserAccountData(address) returns UserAccountData, whose fifth word is
    # totalDebtValueRay: total debt in USD Value units (1e26 per USD), scaled by RAY (1e27).
    def decode_total_debt(raw)
      payload = raw.to_s.delete_prefix("0x")
      raise "Unexpected Aave v4 response: #{raw.inspect}" unless payload.match?(/\A[0-9a-fA-F]{448}\z/)

      total_debt_value_ray = payload[256, 64].to_i(16)
      BigDecimal(total_debt_value_ray.to_s) / (10 ** USD_DEBT_DECIMALS)
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
