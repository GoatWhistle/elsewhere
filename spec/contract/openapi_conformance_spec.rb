require "rails_helper"
require "yaml"

RSpec.describe "OpenAPI conformance", type: :request do
  let(:document) { YAML.safe_load_file(Rails.root.join("docs/04_api/openapi.yaml"), aliases: true) }

  def schema(name)
    { "$ref" => "#/components/schemas/#{name}" }
  end

  def conform!(body, schema_name)
    Elsewhere::Schema.validate!(body, schema(schema_name), root: document, path: schema_name)
  end

  it "answers every endpoint in the shape the contract declares" do
    post "/planning-sessions", params: {
      dream_text: "Вдвоём на неделю к тёплому морю, тихо, до 180000 ₽",
      origin: "MOW",
      date_window: { earliest: "2026-07-01", latest: "2026-07-31", nights_min: 6, nights_max: 7 },
      party: { adults: 2 }
    }, as: :json

    expect(response).to have_http_status(:created)
    session = JSON.parse(response.body)
    conform!(session, "PlanningSession")

    post "/planning-sessions/#{session["id"]}/futures", as: :json
    expect(response).to have_http_status(:accepted)
    conform!(JSON.parse(response.body), "Job")

    get "/planning-sessions/#{session["id"]}/futures"
    expect(response).to have_http_status(:ok)
    listing = JSON.parse(response.body)
    expect(listing.fetch("futures")).not_to be_empty
    listing.fetch("futures").each { |future| conform!(future, "Future") }

    future = listing.fetch("futures").first

    get "/futures/#{future["id"]}"
    expect(response).to have_http_status(:ok)
    conform!(JSON.parse(response.body), "Future")

    post "/futures/#{future["id"]}/simulations", params: { instruction: "Сделай дешевле" }, as: :json
    expect(response).to have_http_status(:accepted)
    job = JSON.parse(response.body)
    conform!(job, "Job")

    result = job.fetch("result")
    case result.fetch("kind")
    when "future" then conform!(result.fetch("future"), "Future")
    when "no_solution" then conform!(result.fetch("no_solution"), "NoSolution")
    else raise "unexpected simulation result #{result.fetch("kind")}"
    end

    get "/futures/#{future["id"]}/forecast"
    expect(response).to have_http_status(:ok)
    conform!(JSON.parse(response.body), "Forecast")
  end

  it "rejects a response that has drifted from the contract" do
    post "/planning-sessions", params: {
      dream_text: "Тест", origin: "MOW",
      date_window: { earliest: "2026-07-01", latest: "2026-07-31", nights_min: 6, nights_max: 7 },
      party: { adults: 2 }
    }, as: :json

    drifted = JSON.parse(response.body).except("travel_dna")

    expect { conform!(drifted, "PlanningSession") }
      .to raise_error(Elsewhere::Schema::Invalid, /missing required property "travel_dna"/)
  end
end
