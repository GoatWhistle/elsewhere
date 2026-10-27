class CreateSupplyCatalogue < ActiveRecord::Migration[8.1]
  def change
    create_table :destinations, id: :uuid do |t|
      t.string :city_code, null: false           # IATA city code — the identifier every other context uses
      t.string :name, null: false
      t.string :country, null: false, default: "RU"
      t.decimal :lat, precision: 9, scale: 6, null: false
      t.decimal :lon, precision: 9, scale: 6, null: false
      t.string :source, null: false              # which harvest produced it
      t.string :source_slug                      # the source's own city slug, so a re-run finds the same pages
      t.string :centre_source, null: false, default: "property_centroid"
      t.timestamps
    end
    add_index :destinations, :city_code, unique: true

    create_table :properties, id: :uuid do |t|
      t.string :catalogue_id, null: false        # "<source>:<their id>" — stable across re-runs
      t.string :source, null: false
      t.references :destination, null: false, foreign_key: true, type: :uuid
      t.string :city_code, null: false           # denormalised: Catalog answers by city_code and never joins for it
      t.string :name, null: false
      t.decimal :lat, precision: 9, scale: 6, null: false
      t.decimal :lon, precision: 9, scale: 6, null: false
      t.string :address
      t.decimal :rating, precision: 3, scale: 1  # on the source's own scale; normalised on read
      t.integer :rating_scale
      t.integer :review_count

      t.integer :price_level_minor
      t.string :price_currency, limit: 3
      t.string :price_level_text                 # the source's own words, kept so the claim stays checkable

      t.jsonb :photos, null: false, default: []
      t.string :source_url, null: false
      t.datetime :harvested_at, null: false
      t.timestamps
    end
    add_index :properties, :catalogue_id, unique: true
    add_index :properties, :city_code

    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE INDEX index_properties_on_point
            ON properties USING GIST ((ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography));
          CREATE INDEX index_destinations_on_point
            ON destinations USING GIST ((ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography));
        SQL
      end
    end
  end
end
