# Converts persisted BasisTradeSnapshot rows into the JSON payload consumed by
# the Basis page chart. Date filtering, serialization and KPI rollups happen
# here on the server; the browser is only responsible for recomputing the
# displayed line as leg toggles change.
class BasisTradeSeriesBuilder
  # Legs are stored in integer subunits and surfaced to the chart as plain
  # decimals divided by this factor so the client can sum them directly.
  CENTS_PER_UNIT = 1_000.0

  def initialize(family:, start_date: nil, end_date: nil, current_reward_reference: nil)
    @family = family
    @start_date = start_date
    @end_date = end_date
    @current_reward_reference = BasisTrade::RewardsValueCalculator.normalize_reference(current_reward_reference)
  end

  def payload
    {
      currency: currency,
      range: range,
      totals: totals,
      points: points
    }
  end

  private
    attr_reader :family, :start_date, :end_date, :current_reward_reference

    def snapshots
      @snapshots ||= begin
        scope = BasisTradeSnapshot.for_family(family).chronological
        scope = scope.where(recorded_at: start_date.beginning_of_day..) if start_date
        scope = scope.where(recorded_at: ..end_date.end_of_day) if end_date
        scope.to_a
      end
    end

    def all_snapshots
      @all_snapshots ||= BasisTradeSnapshot.for_family(family).chronological.to_a
    end

    def currency
      snapshots.last&.currency || family.primary_currency_code
    end

    def range
      {
        start_date: start_date&.iso8601,
        end_date: end_date&.iso8601
      }
    end

    def totals
      baseline = all_snapshots.first
      return { spot: 0.0, short: 0.0, funding: 0.0, rewards: 0.0, combined: 0.0 } if baseline.nil?

      stored_leg_values(baseline)
    end

    def points
      snapshots.map do |snapshot|
        date = snapshot.recorded_at.to_date
        leg_values(snapshot).merge(
          date: date.iso8601,
          date_formatted: I18n.l(date, format: :long)
        )
      end
    end

    def leg_values(snapshot, reward_reference: nil)
      build_leg_payload(
        spot: to_decimal(snapshot.spot_leg_cents),
        short: to_decimal(snapshot.short_leg_cents),
        funding: to_decimal(snapshot.funding_accrued_cents),
        rewards: rewards_value(snapshot, reward_reference: reward_reference),
        lighter_account_value: lighter_account_value_for(snapshot)
      )
    end

    def stored_leg_values(snapshot)
      build_leg_payload(
        spot: to_decimal(snapshot.spot_leg_cents),
        short: to_decimal(snapshot.short_leg_cents),
        funding: to_decimal(snapshot.funding_accrued_cents),
        rewards: to_decimal(snapshot.rewards_accrued_cents),
        lighter_account_value: lighter_account_value_for(snapshot)
      )
    end

    def rewards_value(snapshot, reward_reference: nil)
      reference = reward_reference.presence || reward_reference_for(snapshot)

      BasisTrade::RewardsValueCalculator.new(
        starting_reference: reward_reference_for(all_snapshots.first),
        current_reference: {
          eth_balance: reference&.dig(:eth_balance),
          eth_price_usd: current_reward_reference&.dig(:eth_price_usd).presence || reference&.dig(:eth_price_usd),
          usdc_balance: reference&.dig(:usdc_balance)
        },
        fallback_value: to_decimal(snapshot.rewards_accrued_cents)
      ).value
    end

    def reward_reference_for(snapshot)
      BasisTrade::RewardsValueCalculator.normalize_reference(
        snapshot&.metadata&.dig("rewards_basis") || snapshot&.metadata&.dig(:rewards_basis)
      )
    end

    def build_leg_payload(spot:, short:, funding:, rewards:, lighter_account_value: nil)
      spot = spot.to_f.round(2)
      short = short.to_f.round(2)
      funding = funding.to_f.round(2)
      rewards = rewards.to_f.round(2)
      lighter_account_value = lighter_account_value&.to_f&.round(2)
      combined = if lighter_account_value.present?
        (spot + lighter_account_value).round(2)
      else
        (spot + short + funding + rewards).round(2)
      end

      {
        spot: spot,
        short: short,
        funding: funding,
        rewards: rewards,
        lighter_account_value: lighter_account_value,
        combined: combined
      }
    end

    def lighter_account_value_for(snapshot)
      value = snapshot&.metadata&.dig("lighter", "total_account_value") || snapshot&.metadata&.dig(:lighter, :total_account_value)
      return if value.blank?

      BigDecimal(value.to_s)
    end

    def to_decimal(cents)
      (cents / CENTS_PER_UNIT).round(2)
    end
end
