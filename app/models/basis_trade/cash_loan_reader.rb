require "bigdecimal"
require "json"
require "net/http"
require "uri"

# Reads direct USDC borrows made through Ether.fi Cash on Optimism. It never
# uses total facility debt, which includes unrelated card spending.
class BasisTrade::CashLoanReader
  LOGS_API_URL = "https://optimism.blockscout.com/api".freeze

  # Ether.fi Cash v3's Optimism deployment manifest identifies this proxy as
  # CashEventEmitter. The first block with code at this address was verified via
  # eth_getCode (block 149,521,274; block 149,521,273 returned 0x).
  CASH_EVENT_EMITTER_ADDRESS = "0x380b2e96799405be6e3d965f4044099891881acb".freeze
  CASH_EVENT_EMITTER_DEPLOYMENT_BLOCK = 149_521_274
  USDC_ADDRESS = "0x0b2c639c533813f4aa9d7837caf62653d097ff85".freeze
  USD_DECIMALS = 6
  LOG_PAGE_SIZE = 1_000

  # keccak256("LendBorrowed(address,address,uint256,uint256)"). This differs
  # from CashEventEmitter's Spend event, so card spending is never returned.
  LEND_BORROWED_EVENT_TOPIC = "0x38578014f71a287d9193d79e855fe47d225d8e5637ef400a63adbccfce03fc85".freeze

  def self.topic_address(address)
    "0x#{address.delete_prefix('0x').downcase.rjust(64, '0')}"
  end

  # Returns the all-time direct USDC borrow total for this Cash safe. The Logs
  # V1 API supplies complete historical data in filtered, paginated responses.
  def borrowed_usdc(vault_address:)
    validate_address!(vault_address)

    total = BigDecimal("0")
    page = 1
    loop do
      logs = get_logs_page(vault_address: vault_address, page: page)
      total += logs.sum { |log| decode_amount_in_usd(log.fetch("data")) }
      break if logs.length < LOG_PAGE_SIZE

      page += 1
    end

    total
  end

  private
    def logs_query(vault_address:, page:)
      {
        "module" => "logs",
        "action" => "getLogs",
        "fromBlock" => CASH_EVENT_EMITTER_DEPLOYMENT_BLOCK.to_s,
        "toBlock" => "latest",
        "address" => CASH_EVENT_EMITTER_ADDRESS,
        "topic0" => LEND_BORROWED_EVENT_TOPIC,
        "topic1" => self.class.topic_address(vault_address),
        "topic2" => self.class.topic_address(USDC_ADDRESS),
        # The OptimismScan-compatible endpoint requires all pair connectors
        # when topic2 is supplied, even when every connector is AND.
        "topic0_1_opr" => "and",
        "topic0_2_opr" => "and",
        "topic1_2_opr" => "and",
        "page" => page.to_s,
        "offset" => LOG_PAGE_SIZE.to_s
      }
    end

    def get_logs_page(vault_address:, page:)
      uri = URI(LOGS_API_URL)
      uri.query = URI.encode_www_form(logs_query(vault_address: vault_address, page: page))
      response = http_get(uri)
      raise "Optimism logs API HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      result = body["result"]
      return result if body["status"] == "1" && result.is_a?(Array)
      return [] if result.is_a?(Array) && body["message"].to_s.casecmp?("No logs found")

      raise "Optimism logs API error: #{body['message'] || body['result'] || 'unexpected response'}"
    rescue JSON::ParserError => error
      raise "Optimism logs API returned invalid JSON: #{error.message}"
    end

    def http_get(uri, redirects_remaining: 3)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 15) do |http|
        http.get(uri.request_uri)
      end
      return response unless response.is_a?(Net::HTTPRedirection) && redirects_remaining.positive?

      location = response["location"]
      raise "Optimism logs API redirect missing Location" if location.nil? || location.empty?

      http_get(URI.join(uri, location), redirects_remaining: redirects_remaining - 1)
    end

    def decode_amount_in_usd(raw)
      payload = raw.to_s.delete_prefix("0x")
      unless payload.match?(/\A[0-9a-fA-F]{128}\z/)
        raise "Unexpected Ether.fi CashEventEmitter LendBorrowed event: #{raw.inspect}"
      end

      amount_in_usd = payload[64, 64].to_i(16)
      BigDecimal(amount_in_usd.to_s) / (10 ** USD_DECIMALS)
    end

    def validate_address!(address)
      unless address.to_s.match?(/\A0x[0-9a-fA-F]{40}\z/)
        raise ArgumentError, "Invalid vault address: #{address.inspect}"
      end
    end
end
