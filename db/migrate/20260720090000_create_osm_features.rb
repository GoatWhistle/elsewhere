class CreateOsmFeatures < ActiveRecord::Migration[8.1]
  def change
    create_table :osm_features do |t|
      t.string :city_code, null: false      # which corpus extract this came from
      t.string :layer, null: false          # place | aerodrome | poi | road | coastline
      t.string :osm_type, null: false       # node | way | relation
      t.bigint :osm_id, null: false
      t.jsonb :tags, null: false, default: {}
      t.datetime :imported_at, null: false
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL
          ALTER TABLE osm_features ADD COLUMN geom geometry(Geometry, 4326) NOT NULL;
          CREATE INDEX index_osm_features_on_geom ON osm_features USING GIST (geom);
          CREATE INDEX index_osm_features_on_city_and_layer ON osm_features (city_code, layer);
          CREATE UNIQUE INDEX index_osm_features_on_identity
            ON osm_features (city_code, layer, osm_type, osm_id);
        SQL
      end
    end

  end
end
