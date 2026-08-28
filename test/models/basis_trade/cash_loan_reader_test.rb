require "test_helper"

class BasisTrade::CashLoanReaderTest < ActiveSupport::TestCase
  SAFE_ADDRESS = "0xe046ef5e90f6d0a6b9dbb4d98541986b39c95836".freeze

  setup do
    @reader = BasisTrade::CashLoanReader.new
  end

  test "sums every page of filtered direct USDC LendBorrowed logs" do
    first_page = [ event(amount_in_usd: 248_000_000), event(amount_in_usd: 12_500_000) ] + Array.new(BasisTrade::CashLoanReader::LOG_PAGE_SIZE - 2) { event(amount_in_usd: 0) }
    @reader.expects(:get_logs_page).with(vault_address: SAFE_ADDRESS, page: 1).returns(first_page)
    @reader.expects(:get_logs_page).with(vault_address: SAFE_ADDRESS, page: 2).returns([])

    assert_equal BigDecimal("260.5"), @reader.borrowed_usdc(vault_address: SAFE_ADDRESS)
  end

  test "requests all topic connectors required when filtering the USDC topic" do
    @reader.expects(:get_logs_page).with(vault_address: SAFE_ADDRESS, page: 1).returns([])

    @reader.borrowed_usdc(vault_address: SAFE_ADDRESS)

    expected_query = {
      "module" => "logs",
      "action" => "getLogs",
      "fromBlock" => BasisTrade::CashLoanReader::CASH_EVENT_EMITTER_DEPLOYMENT_BLOCK.to_s,
      "toBlock" => "latest",
      "address" => BasisTrade::CashLoanReader::CASH_EVENT_EMITTER_ADDRESS,
      "topic0" => BasisTrade::CashLoanReader::LEND_BORROWED_EVENT_TOPIC,
      "topic1" => BasisTrade::CashLoanReader.topic_address(SAFE_ADDRESS),
      "topic2" => BasisTrade::CashLoanReader.topic_address(BasisTrade::CashLoanReader::USDC_ADDRESS),
      "topic0_1_opr" => "and",
      "topic0_2_opr" => "and",
      "topic1_2_opr" => "and",
      "page" => "1",
      "offset" => BasisTrade::CashLoanReader::LOG_PAGE_SIZE.to_s
    }
    assert_equal expected_query, @reader.send(:logs_query, vault_address: SAFE_ADDRESS, page: 1)
  end

  test "raises an actionable error when the logs API reports a failure" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@body, JSON.generate(status: "0", message: "NOTOK: rate limited", result: "Max rate limit reached"))
    response.instance_variable_set(:@read, true)
    @reader.expects(:http_get).returns(response)

    error = assert_raises(RuntimeError) do
      @reader.send(:get_logs_page, vault_address: SAFE_ADDRESS, page: 1)
    end
    assert_equal "Optimism logs API error: NOTOK: rate limited", error.message
  end

  test "rejects malformed LendBorrowed event data" do
    @reader.expects(:get_logs_page).with(vault_address: SAFE_ADDRESS, page: 1).returns([
      { "data" => "0x00" }
    ])

    assert_raises(RuntimeError) { @reader.borrowed_usdc(vault_address: SAFE_ADDRESS) }
  end

  test "requires a valid safe address" do
    assert_raises(ArgumentError) { @reader.borrowed_usdc(vault_address: "") }
    assert_raises(ArgumentError) { @reader.borrowed_usdc(vault_address: "not-an-address") }
  end

  private
    def event(amount_in_usd:)
      { "data" => "0x#{'0'.rjust(64, '0')}#{amount_in_usd.to_s(16).rjust(64, '0')}" }
    end
end
