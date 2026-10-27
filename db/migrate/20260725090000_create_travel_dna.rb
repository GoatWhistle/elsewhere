class CreateTravelDna < ActiveRecord::Migration[8.1]
  def change
    create_table :travel_dna_versions, id: :uuid do |t|
      t.uuid :session_id, null: false
      t.integer :version, null: false
      t.uuid :parent_id
      t.jsonb :unmatched_intent, null: false, default: []
      t.boolean :degraded, null: false, default: false   # the model never answered for this version
      t.string :degraded_reason
      t.timestamps
    end
    add_index :travel_dna_versions, %i[session_id version], unique: true

    create_table :travel_dna_elements, id: :uuid do |t|
      t.references :travel_dna_version, null: false, foreign_key: true, type: :uuid
      t.string :dimension, null: false
      t.string :kind, null: false
      t.jsonb :target                                    # shape depends on the dimension
      t.decimal :weight, precision: 4, scale: 3          # null for a hard constraint: it disqualifies, it does not compete
      t.decimal :tolerance, precision: 6, scale: 3
      t.string :provenance, null: false
      t.decimal :confidence, precision: 4, scale: 3, null: false
      t.integer :position, null: false, default: 0       # the ranking the weights came from

      t.string :derived_from
      t.timestamps
    end
    add_index :travel_dna_elements, %i[travel_dna_version_id dimension], unique: true
  end
end
