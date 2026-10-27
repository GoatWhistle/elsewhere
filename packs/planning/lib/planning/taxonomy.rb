module Planning
  module Taxonomy
    WEIGHT_SCALE = (0.0..1.0).freeze

    FAMILIES = {
      "sea_access" => :more_is_better, "food_quality" => :more_is_better, "walkability" => :more_is_better,
      "quiet" => :more_is_better, "comfort" => :more_is_better, "transfer_simplicity" => :more_is_better,
      "climate_warm" => :target, "nature_vs_city" => :target, "crowds" => :target, "nightlife" => :target,
      "total_budget" => :hard, "trip_length" => :hard, "dates" => :hard, "car_free" => :hard
    }.freeze

    KINDS = Hash.new("preference").merge(
      "crowds" => "aversion",
      "total_budget" => "hard_constraint", "trip_length" => "hard_constraint",
      "dates" => "hard_constraint", "car_free" => "hard_constraint"
    ).freeze

    HARD = %w[total_budget trip_length dates party car_free].freeze

    UNMEASURABLE = %w[crowds nightlife].freeze

    module_function

    def all = FAMILIES.keys
    def family(dimension) = FAMILIES[dimension]
    def kind(dimension) = KINDS[dimension]
    def hard?(dimension) = FAMILIES[dimension] == :hard
    def scored?(dimension) = !hard?(dimension)
    def measurable?(dimension) = scored?(dimension) && !UNMEASURABLE.include?(dimension)
    def known?(dimension) = FAMILIES.key?(dimension)
  end
end
