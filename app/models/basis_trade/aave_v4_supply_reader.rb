require "json"
require "net/http"

# Reads a Cash Safe's supplied weETH from ether.fi's Optimism Aave v4 Spoke.
# The Hub custody balance is shared liquidity; individual ownership is recorded
# by the Spoke, so it must not be inferred from the Hub's ERC-20 balance.
class BasisTrade::AaveV4SupplyReader
  RPC_URL = "https://mainnet.optimism.io".freeze

  # ether.fi's official Optimism Aave v4 deployment. See:
  # https://etherfi.gitbook.io/etherfi/products/borrow/lending-market-parameters
  HUB_ADDRESS = "0x66753c4e3fC84f1eD0e3C267C927284E9d90C572".freeze
  SPOKE_ADDRESS = "0xdffcC3536D932eb51Df51a7F5FA407c4270d5308".freeze
  WEETH_ADDRESS = "0x5A7fACB970D094B6C7FF1df0eA68D99E6e73CBFF".freeze
  WEETH_DECIMALS = 18

  # keccak256("getAssetId(address)")[0, 4]
  GET_ASSET_ID_SELECTOR = "d6abe642".freeze
  # keccak256("getReserveId(address,uint256)")[0, 4]
  GET_RESERVE_ID_SELECTOR = "42aef1f1".freeze
  # keccak256("getUserSuppliedAssets(uint256,address)")[0, 4]
  GET_USER_SUPPLIED_ASSETS_SELECTOR = "f1568a89".freeze

  # Returns zero for tokens that are not in the migrated weETH position. This
  # keeps caller-configured direct ERC-20 valuation and reward handling intact.
  def supplied_balance(token_address:, safe_address:)
    return BigDecimal("0") unless token_address.to_s.casecmp?(WEETH_ADDRESS)

    validate_address!(safe_address, "safe_address")
    asset_id = uint256_call(HUB_ADDRESS, "#{GET_ASSET_ID_SELECTOR}#{encoded_address(WEETH_ADDRESS)}")
    reserve_id = uint256_call(SPOKE_ADDRESS, "#{GET_RESERVE_ID_SELECTOR}#{encoded_address(HUB_ADDRESS)}#{encoded_uint256(asset_id)}")
    units = uint256_call(SPOKE_ADDRESS, "#{GET_USER_SUPPLIED_ASSETS_SELECTOR}#{encoded_uint256(reserve_id)}#{encoded_address(safe_address)}")

    BigDecimal(units.to_s) / (10 ** WEETH_DECIMALS)
  end

  private
    def uint256_call(to, data)
      raw = rpc_call("eth_call", [ { to: to, data: "0x#{data}" }, "latest" ])
      payload = raw.to_s.delete_prefix("0x")
      raise "Unexpected Aave v4 response: #{raw.inspect}" unless payload.match?(/\A[0-9a-fA-F]{64}\z/)

      payload.to_i(16)
    end

    def encoded_address(address)
      validate_address!(address, "address")
      address.delete_prefix("0x").downcase.rjust(64, "0")
    end

    def encoded_uint256(value)
      value.to_i.to_s(16).rjust(64, "0")
    end

    def validate_address!(address, name)
      raise ArgumentError, "#{name} must be a 20-byte address" unless address.to_s.match?(/\A0x[0-9a-fA-F]{40}\z/)
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
