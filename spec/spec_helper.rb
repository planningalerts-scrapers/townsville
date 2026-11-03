# frozen_string_literal: true

require "bundler/setup"

# Started before the scraper is loaded, so all of it is measured
require "simplecov"
require "simplecov-console"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  add_filter "/vendor/"
end

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::Console,
  ]
)

require_relative "../scraper"

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
