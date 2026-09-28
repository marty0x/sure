class AddCspBucketToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_column :accounts, :csp_bucket, :string
  end
end
