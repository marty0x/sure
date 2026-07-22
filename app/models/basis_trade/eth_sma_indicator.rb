# Compares the current ETH/USD price against its trailing N-day simple
# moving average (WINDOW_DAYS), to signal whether Ether.fi rewards should be
# redeemed in weETH (price below its SMA) or kept in USDC (price above its
# SMA).
#
# Calls Provider::BinancePublic directly rather than going through the
# Security/Security::Price provider-registry machinery: that path is gated by
# Setting.enabled_securities_providers, which defaults to "twelve_data" and
# would silently no-op for a Binance-only lookup unless the family has opted
# a crypto provider into their securities settings.
module BasisTrade
  class EthSmaIndicator
    WINDOW_DAYS = 200
    TICKER = "ETHUSD"
    CACHE_TTL = 1.hour

    def summary
      # Keyed by WINDOW_DAYS so changing the window can't serve a stale value
      # computed under a different window out of the (Redis-backed) cache.
      Rails.cache.fetch("basis_trade/eth_sma_indicator:#{WINDOW_DAYS}d", expires_in: CACHE_TTL) { compute_summary }
    end

    private
      def compute_summary
        # Pad the window so weekends/gaps in the provider's daily candles don't
        # leave us short of WINDOW_DAYS closes.
        start_date = Date.current - (WINDOW_DAYS + 15).days

        response = Provider::BinancePublic.new.fetch_security_prices(
          symbol: TICKER,
          exchange_operating_mic: Provider::BinancePublic::BINANCE_MIC,
          start_date: start_date,
          end_date: Date.current
        )
        return nil unless response.success? && response.data.present?

        prices = response.data.sort_by(&:date).last(WINDOW_DAYS)
        return nil if prices.size < WINDOW_DAYS

        current_price = prices.last.price
        sma = (prices.sum(&:price) / prices.size).round(2)

        {
          current_price: current_price,
          sma: sma,
          above: current_price >= sma,
          trend: Trend.new(current: current_price, previous: sma, favorable_direction: "up")
        }
      rescue => e
        Rails.logger.error("BasisTrade::EthSmaIndicator failed: #{e.message}")
        nil
      end
  end
end
