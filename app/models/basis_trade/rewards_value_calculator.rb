class BasisTrade::RewardsValueCalculator
  def self.normalize_reference(value)
    return if value.blank?

    {
      eth_balance: decimal_or_nil(value["eth_balance"] || value[:eth_balance]),
      eth_price_usd: decimal_or_nil(value["eth_price_usd"] || value[:eth_price_usd]),
      usdc_balance: decimal_or_nil(value["usdc_balance"] || value[:usdc_balance])
    }
  end

  def initialize(starting_reference:, current_reference:, fallback_value: 0.0)
    @starting_reference = starting_reference
    @current_reference = current_reference
    @fallback_value = fallback_value.to_f
  end

  def value
    return fallback_value if starting_reference.blank? || current_reference.blank?

    starting_eth_balance = starting_reference[:eth_balance]
    eth_balance = current_reference[:eth_balance]
    eth_price_usd = current_reference[:eth_price_usd]
    usdc_balance = current_reference[:usdc_balance]

    return fallback_value if [ starting_eth_balance, eth_balance, eth_price_usd, usdc_balance ].any?(&:nil?)

    (((eth_balance - starting_eth_balance) * eth_price_usd) + usdc_balance).round(2).to_f
  end

  private
    attr_reader :starting_reference, :current_reference, :fallback_value

    def self.decimal_or_nil(value)
      return if value.nil? || value == ""

      BigDecimal(value.to_s)
    end

    private_class_method :decimal_or_nil
  end
