class PropertyGeoFeatureRecord < ActiveRecord::Base
  self.table_name = "property_geo_features"

  belongs_to :property, class_name: "PropertyRecord", foreign_key: :property_id
end
