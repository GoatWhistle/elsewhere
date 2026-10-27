require_relative "../packs/supply/lib/supply"

summary = Supply::Corpus.seed!(log: ->(line) { puts line })
puts summary

coverage = Supply::Corpus.coverage
puts "geography: #{coverage["geography"].map { |type, n| "#{type}=#{n}" }.join(" ")}"
puts "gaps: #{coverage["gaps"].empty? ? "none" : coverage["gaps"].join("; ")}"
