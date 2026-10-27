class AddGeographyTypeToDestinations < ActiveRecord::Migration[8.1]
  def change
    add_column :destinations, :geography_type, :string
    add_index :destinations, :geography_type
  end
end
