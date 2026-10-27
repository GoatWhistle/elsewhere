class WidenPriceLevelAndNoteIt < ActiveRecord::Migration[8.1]
  def change
    change_column :properties, :price_level_minor, :bigint

    add_column :properties, :price_level_note, :string
  end
end
