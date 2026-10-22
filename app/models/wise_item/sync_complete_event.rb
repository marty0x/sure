# frozen_string_literal: true

class WiseItem::SyncCompleteEvent
  attr_reader :wise_item

  def initialize(wise_item)
    @wise_item = wise_item
  end

  def broadcast

    wise_item.family.broadcast_sync_complete unless wise_item.part_of_larger_sync?
  end

  private

    def dom_id(record)
      "#{record.class.name.underscore}_#{record.id}"
    end
end
