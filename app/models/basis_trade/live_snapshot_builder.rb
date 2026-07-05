class BasisTrade::LiveSnapshotBuilder
  Result = Struct.new(:configured, :snapshot, :error, keyword_init: true)

  REWARD_USDC_TOKEN_ADDRESSES = %w[
    0x0b2c639c533813f4aa9d7837caf62653d097ff85
    0x7f5c764cbc14f9669b88837ca1490cca17c31607
  ].freeze
  REWARD_ETH_SYMBOLS = %w[WEETH WETH ETH].freeze
  REWARD_STABLE_SYMBOLS = %w[USDC USDC.E].freeze

  def initialize(family:)
    @family = family
  end

  def call
    return Result.new(configured: false) unless @family.basis_trade_sources_configured?

    snapshot = {
      recorded_at: Time.current,
      currency: @family.primary_currency_code,
      spot_leg_cents: 0,
      short_leg_cents: 0,
      funding_accrued_cents: 0,
      rewards_accrued_cents: 0,
      metadata: {}
    }

    if @family.basis_long_address.present?
      valuator = BasisTrade::OptimismWalletValuator.new
      spot_leg = valuator.value(
        address: @family.basis_long_address,
        token_addresses: @family.basis_long_token_addresses_array
      )
      reward_usdc = valuator.value(
        address: @family.basis_long_address,
        token_addresses: reward_usdc_token_addresses
      )

      snapshot[:spot_leg_cents] = dollars_to_cents(spot_leg[:total_value])
      snapshot[:metadata][:spot_tokens] = spot_leg[:tokens]
      snapshot[:metadata][:reward_tokens] = reward_usdc[:tokens]
      snapshot[:metadata][:rewards_basis] = rewards_basis_for(
        spot_tokens: spot_leg[:tokens],
        reward_tokens: reward_usdc[:tokens]
      )
      snapshot[:rewards_accrued_cents] = dollars_to_cents(reward_usdc[:total_value])
    end

    if @family.basis_lighter_address.present?
      lighter_summary = Provider::Lighter.new.total_account_value_for_l1_address(@family.basis_lighter_address)
      snapshot[:short_leg_cents] = dollars_to_cents(lighter_summary[:total_position_notional])
      snapshot[:funding_accrued_cents] = dollars_to_cents(lighter_summary[:funding_accrued])
      snapshot[:metadata][:lighter] = lighter_summary
    end

    Result.new(configured: true, snapshot: snapshot)
  rescue StandardError => error
    Result.new(configured: true, error: error.message)
  end

  private

    def dollars_to_cents(value)
      (BigDecimal(value.to_s) * 100).round(0).to_i
    end

    def reward_usdc_token_addresses
      configured = @family.basis_long_token_addresses_array
      REWARD_USDC_TOKEN_ADDRESSES.reject { |address| configured.include?(address) }
    end

    def rewards_basis_for(spot_tokens:, reward_tokens:)
      eth_token = spot_tokens.find { |token| REWARD_ETH_SYMBOLS.include?(token[:symbol].to_s.upcase) }
      usdc_token = reward_tokens.find { |token| REWARD_STABLE_SYMBOLS.include?(token[:symbol].to_s.upcase) }

      {
        eth_balance: BigDecimal(eth_token&.dig(:balance).to_s.presence || "0"),
        eth_price_usd: BigDecimal(eth_token&.dig(:price_usd).to_s.presence || "0"),
        usdc_balance: BigDecimal(usdc_token&.dig(:balance).to_s.presence || "0")
      }
    end
end
