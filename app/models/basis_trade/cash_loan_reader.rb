require "bigdecimal"
require "json"
require "net/http"
require "uri"

# Reads the live Ether.fi Credit debt recorded for a Cash Safe on Optimism.
class BasisTrade::CashLoanReader
  RPC_URL = "https://mainnet.optimism.io".freeze
  LEND_GATEWAY_ADDRESS = "0x01F8cDFb1694eA8fE4ED6c38a0fD78d1188E03F4".freeze
  GET_ACCOUNT_DATA_SELECTOR = "5d78650e".freeze
  USD_DECIMALS = 6
  ACCOUNT_DATA_WORD_COUNT = 5
  DEBT_USD_WORD_INDEX = 1

  # Returns the Cash Safe's current Ether.fi Credit debt in USD. Account data
  # contains five uint256 words; debtUsd is the second (zero-index 1) value.
  def borrowed_usdc(vault_address:)
    validate_address!(vault_address)

    raw = rpc_call(
      "eth_call",
      [
        {
          to: LEND_GATEWAY_ADDRESS,
          data: "0x#{GET_ACCOUNT_DATA_SELECTOR}#{encoded_address(vault_address)}"
        },
        "latest"
      ]
    )
    debt_usd = decode_debt_usd(raw)

    BigDecimal(debt_usd.to_s) / (10 ** USD_DECIMALS)
  end

  private
    def decode_debt_usd(raw)
      payload = raw.to_s.delete_prefix("0x")
      unless payload.match?(/\A[0-9a-fA-F]{#{ACCOUNT_DATA_WORD_COUNT * 64}}\z/)
        raise "Unexpected Ether.fi Cash LendGateway account data response"
      end

      payload[DEBT_USD_WORD_INDEX * 64, 64].to_i(16)
    end

    def encoded_address(address)
      address.delete_prefix("0x").downcase.rjust(64, "0")
    end

    def validate_address!(address)
      unless address.to_s.match?(/\A0x[0-9a-fA-F]{40}\z/)
        raise ArgumentError, "Invalid vault address: #{address.inspect}"
      end
    end

    def rpc_call(method, params)
      uri = URI(RPC_URL)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
      raise "Optimism RPC request failed with status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      raise "Optimism RPC error: #{parsed['error']}" if parsed["error"].present?

      parsed.fetch("result")
    rescue JSON::ParserError => error
      raise "Optimism RPC returned invalid JSON: #{error.message}"
    end
end
