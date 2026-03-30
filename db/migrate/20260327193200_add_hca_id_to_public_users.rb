class AddHcaIdToPublicUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :public_users, :hca_id, :string unless column_exists?(:public_users, :hca_id)
    add_index :public_users, :hca_id, unique: true unless index_exists?(:public_users, :hca_id)
  end
end
