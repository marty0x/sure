class BasisTrade::SnapshotRecorder
  def initialize(family:, recorded_at: Time.current, live_snapshot_builder: nil)
    @family = family
    @recorded_at = recorded_at
    @live_snapshot_builder = live_snapshot_builder || BasisTrade::LiveSnapshotBuilder.new(family: family)
  end

  def call
    result = @live_snapshot_builder.call
    return unless result.configured
    raise StandardError, result.error if result.error.present?

    snapshot = @family.basis_trade_snapshots.find_or_initialize_by(recorded_at: @recorded_at)
    snapshot.assign_attributes(
      spot_leg_cents: cents_to_snapshot_units(result.snapshot[:spot_leg_cents]),
      short_leg_cents: -cents_to_snapshot_units(result.snapshot[:short_leg_cents].abs),
      funding_accrued_cents: cents_to_snapshot_units(result.snapshot[:funding_accrued_cents]),
      rewards_accrued_cents: cents_to_snapshot_units(result.snapshot[:rewards_accrued_cents]),
      currency: result.snapshot[:currency],
      metadata: normalized_metadata(result.snapshot[:metadata])
    )
    snapshot.save!
    snapshot
  end

  private

    def cents_to_snapshot_units(value)
      (BigDecimal(value.to_s) * (BasisTradeSeriesBuilder::CENTS_PER_UNIT / 100.0)).round(0).to_i
    end

    def normalized_metadata(value)
      case value
      when Hash
        value.deep_stringify_keys.transform_values { |nested| normalized_metadata(nested) }
      when Array
        value.map { |nested| normalized_metadata(nested) }
      when BigDecimal
        value.to_s("F")
      else
        value
      end
    end
end
