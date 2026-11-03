#!/usr/bin/env ruby
# frozen_string_literal: true

# Scrapes development applications for Townsville City Council.
#
# The council's ePlanning site (XC.Track) lists every application lodged in a
# period (this week, this month, last month and so on) on a single page. All
# the results are in the page, and paged in the browser with JavaScript. Each
# application is a div.result holding the reference link, the description,
# one or more addresses and a hidden "More" div with the lodged date.
#
# Applications on public notification have their own list in the same
# format. Their notification dates are only on each application's details
# page, so those are fetched too.
#
# The site's XML output (o=xml), which the multiple_icon scraper relies on,
# returns an error page.
#
# See https://github.com/planningalerts-scrapers/issues/issues/1460

require "bundler/setup"
Bundler.require

require "scraperwiki"
require "mechanize"
require "date"

class Scraper
  BASE_URL = "https://eplanning.townsville.qld.gov.au/Pages/XC.Track/"
  SEARCH_URL = "#{BASE_URL}SearchApplication.aspx".freeze
  NOTIFICATION_URL = "#{BASE_URL}SearchApplicationNotif.aspx?e=y".freeze
  # Development, building and plumbing application types, as in the site's own
  # "Received this month" menu links
  TYPES = %w[PDMCUCode PDMCUimp PDOpWorks PDReconfig QMCU QRAL QOPW QDBW QPOS QEXC QSPS QCAR PDSAMCUse PDSARecon
             PDSAOpWks].freeze

  # Last month as well as this month, so there are always at least 30 days of
  # applications early in the month
  DEFAULT_PERIODS = %w[thismonth lastmonth].freeze
  PERIODS = %w[thisweek lastweek thismonth lastmonth].freeze

  # An application missing something PlanningAlerts needs is skipped with a
  # warning, but the run stops once there are more than 10 + 20% of good ones
  class BadApplication < StandardError; end

  def self.run
    new.run
  end

  def initialize
    @agent = Mechanize.new
    if ENV["MORPH_AUSTRALIAN_PROXY"]
      # On morph.io set the environment variable MORPH_AUSTRALIAN_PROXY to
      # http://morph:password@au.proxy.oaf.org.au:8888 replacing password with
      # the real password.
      puts "Using Australian proxy..."
      @agent.agent.set_proxy(ENV["MORPH_AUSTRALIAN_PROXY"])
    end
    @debug = !ENV["MORPH_DEBUG"].to_s.empty?
    @requests = 0
    # References saved, as an application can be in more than one list
    @saved = Set.new
    @skipped = 0
  end

  def run
    puts "Running ruby #{RUBY_VERSION}"
    periods.each { |period| scrape_lodged(period) }
    # Last, so the notification dates are kept when an application is in both
    scrape_on_notification
    # Doesn't check which records are new, so reports them all as saved
    puts "", "Finished - saved #{@saved.size} records#{", skipped #{@skipped} bad applications" if @skipped.positive?}"
  end

  private

  # MORPH_PERIOD picks a single period, for example lastweek, for data recovery
  def periods
    period = ENV["MORPH_PERIOD"].to_s
    return DEFAULT_PERIODS if period.empty?
    return [period] if PERIODS.include?(period)

    raise "Unknown MORPH_PERIOD #{period.inspect}, expected one of #{PERIODS.join(', ')}"
  end

  def scrape_lodged(period)
    url = "#{SEARCH_URL}?d=#{period}&k=LodgementDate&t=#{TYPES.join(',')}"
    puts "", "Scraping applications lodged #{period}..."
    results = results(get(url), url)
    puts "No applications lodged #{period}" if results.empty?

    results.each_with_index do |result, index|
      save_result("#{period} result #{index + 1}") { parse_result(result) }
    end
    puts "Finished #{period} - processed #{results.size} records"
  end

  def scrape_on_notification
    puts "", "Scraping applications on public notification..."
    results = results(get(NOTIFICATION_URL), NOTIFICATION_URL)
    puts "No applications on public notification" if results.empty?

    results.each_with_index do |result, index|
      save_result("on notification result #{index + 1}") do
        record = parse_result(result)
        record.merge(notification_dates(record))
      end
    end
    puts "Finished on notification - processed #{results.size} records"
  end

  # Waits a second between requests to be gentle on the council's site
  def get(url)
    sleep 1 if @requests.positive?
    @requests += 1
    @agent.get(url)
  end

  # Returns the results on the page, checked against the count the page
  # states. A period with no applications is normal, for example a quiet 1st
  # of the month, and the page may then not give a count. PlanningAlerts flags
  # long gaps itself.
  def results(page, url)
    results = page.search("#hiddenresult div.result")
    summary = page.search("div").map { |div| clean_text(div.text) }
                  .find { |text| text.match?(/\A\d+ applications? found/) }
    return results if summary.nil? && results.empty?
    raise "No results summary found at #{url}" if summary.nil?

    expected = summary.to_i
    raise "Expected #{expected} applications but found #{results.size} at #{url}" unless results.size == expected

    results
  end

  def save_result(position)
    save(yield)
  rescue BadApplication => e
    @skipped += 1
    puts "Skipping bad application (#{position}): #{e.message}"
    return if @skipped <= 10 + (@saved.size / 5.0)

    raise "Too many bad applications: skipped #{@skipped}, saved #{@saved.size}"
  end

  # Raises BadApplication when the reference or address is missing, as
  # PlanningAlerts can't use the record without them
  def parse_result(result)
    link = result.at("a.search")
    reference = clean_text(link.text)
    raise BadApplication, "no application number" if reference.empty?

    # The first address is the main one. The lodged date and status are in
    # the "More" div, which has strong tags of its own.
    address = clean_text(result.at("> strong")&.text)
    raise BadApplication, "#{reference} has no address" if address.empty?

    {
      "council_reference" => reference,
      "address" => address,
      "description" => description(result),
      "info_url" => info_url(link),
      "date_scraped" => Date.today.to_s,
      "date_received" => parse_date(reference, "lodged", lodged(result)),
    }.compact
  end

  # The description is the first line of text after the reference. Falls back
  # to "Development Application" when there isn't one.
  def description(result)
    text = result.xpath("text()").map { |node| clean_text(node.text) }.find { |line| !line.empty? }
    text.nil? || text == "Address:" ? "Development Application" : text
  end

  # Falls back to the search page when a result has no details link
  def info_url(link)
    href = link["href"].to_s
    href.empty? ? SEARCH_URL : URI.join(BASE_URL, href).to_s
  end

  # The lodged date is followed by the status in brackets
  def lodged(result)
    clean_text(result.at("div[id^='More']").text)[/Lodged:([^(]*)/, 1].to_s.strip
  end

  # Reads the notification start and end dates from the details page history
  def notification_dates(record)
    return {} if record["info_url"] == SEARCH_URL

    reference = record["council_reference"]
    rows = get(record["info_url"]).search("#events tr")
    raise "No history found at #{record['info_url']}" if rows.empty?

    history = rows.to_h do |row|
      cells = row.search("td").map { |cell| clean_text(cell.text) }
      [cells.first, cells.last]
    end
    {
      "on_notice_from" => parse_date(reference, "notification start", history["Start Date of Notification"]),
      "on_notice_to" => parse_date(reference, "notification end", history["End Date of Notification"]),
    }.compact
  end

  # Leaves the date out, with a warning, when it can't be read
  def parse_date(reference, name, date)
    Date.strptime(date.to_s, "%d/%m/%Y").to_s
  rescue Date::Error
    puts "Warning: #{reference} has an unreadable #{name} date #{date.inspect}"
    nil
  end

  # Collapses whitespace, including any non-breaking spaces
  def clean_text(text)
    text.to_s.gsub(/[[:space:]]+/, " ").strip
  end

  def save(record)
    puts "Storing #{record['council_reference']} - #{record['address']}"
    puts "RECORD: #{record.inspect}" if @debug
    ScraperWiki.save_sqlite(["council_reference"], record)
    @saved << record["council_reference"]
  end
end

# :nocov:
Scraper.run if __FILE__ == $PROGRAM_NAME
# :nocov:
