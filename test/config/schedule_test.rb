require "minitest/autorun"
require "pathname"
require "yaml"

class ScheduleTest < Minitest::Test
  def test_records_basis_snapshots_at_the_two_established_utc_boundaries
    schedule_path = Pathname.new(__dir__).join("../../config/schedule.yml")
    schedule = YAML.safe_load_file(schedule_path)

    assert_equal "0 */12 * * *", schedule.fetch("record_basis_snapshots").fetch("cron")
  end
end
