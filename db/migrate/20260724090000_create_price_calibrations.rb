class CreatePriceCalibrations < ActiveRecord::Migration[8.1]
  def change
    add_column :destinations, :peak_season, :string

    create_table :price_calibrations, id: :uuid do |t|
      t.string :city_code, null: false
      t.integer :month, null: false
      t.string :model_version, null: false

      t.decimal :comfort, precision: 4, scale: 3          # 0–1, how much this month suits this destination
      t.decimal :popularity, precision: 4, scale: 3       # 0–1, how busy the destination is at all
      t.decimal :amplitude, precision: 4, scale: 3        # how far the factor may swing here
      t.decimal :seasonal_factor, precision: 4, scale: 3, null: false

      t.jsonb :inputs, null: false, default: {}
      t.datetime :computed_at, null: false
      t.timestamps
    end
    add_index :price_calibrations, %i[city_code month model_version], unique: true
  end
end
