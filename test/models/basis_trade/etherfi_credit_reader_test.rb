require "bigdecimal"
require "minitest/autorun"

module BasisTrade
end

require_relative "../../../app/models/basis_trade/etherfi_credit_reader"

class BasisTrade::EtherfiCreditReaderTest < Minitest::Test
  SAFE_ADDRESS = "0xe046ef5e90f6d0a6b9dbb4d98541986b39c95836".freeze

  def setup
    @reader = BasisTrade::EtherfiCreditReader.new
  end

  def test_reads_current_debt_usd_from_lend_gateway
    response = "0x#{encoded_word(1)}#{encoded_word(2_513_979_896)}#{encoded_word(3)}#{encoded_word(4)}#{encoded_word(5)}"
    expected_params = [
      {
        to: BasisTrade::EtherfiCreditReader::LEND_GATEWAY_ADDRESS,
        data: "0x#{BasisTrade::EtherfiCreditReader::GET_ACCOUNT_DATA_SELECTOR}#{encoded_address(SAFE_ADDRESS)}"
      },
      "latest"
    ]
    @reader.define_singleton_method(:rpc_call) do |method, params|
      raise "unexpected RPC call" unless method == "eth_call" && params == expected_params

      response
    end

    assert_equal BigDecimal("2513.979896"), @reader.borrowing_usd(vault_address: SAFE_ADDRESS)
  end

  def test_rejects_incomplete_gateway_response
    incomplete_response = "0x#{encoded_word(1)}"
    @reader.define_singleton_method(:rpc_call) { |_method, _params| incomplete_response }

    assert_raises(RuntimeError) { @reader.borrowing_usd(vault_address: SAFE_ADDRESS) }
  end

  private

    def encoded_address(address)
      address.delete_prefix("0x").downcase.rjust(64, "0")
    end

    def encoded_word(value)
      value.to_s(16).rjust(64, "0")
    end
end
