class AddCspBucketToCategories < ActiveRecord::Migration[7.2]
  def change
    add_column :categories, :csp_bucket, :string
  end
end
