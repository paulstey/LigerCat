class CreatePublicationDates < ActiveRecord::Migration
  def self.up
    create_table :publication_dates do |t|
      t.integer :query_id
      t.integer :year
      t.integer :publication_count

      t.timestamps
    end
    add_index :publication_dates, :query_id
  end

  def self.down
    drop_table :publication_dates
  end
end