# frozen_string_literal: true

RSpec.describe Scraper do
  let(:lodged) { fixture("lodged.html") }
  let(:notification) { fixture("notification.html") }
  let(:details) { fixture("details.html") }
  let(:saved) { [] }
  let(:requested) { [] }

  around do |example|
    period = ENV.delete("MORPH_PERIOD")
    example.run
  ensure
    ENV["MORPH_PERIOD"] = period
  end

  before do
    allow(ScraperWiki).to receive(:save_sqlite) { |_keys, record| saved << record }
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  def fixture(name)
    File.read(File.join(__dir__, "fixtures", name))
  end

  # Runs the scraper with each kind of request answered by its page, and
  # returns its output
  def run_with(lodged_html: lodged, notification_html: notification, details_html: details, period: "thisweek")
    ENV["MORPH_PERIOD"] = period
    allow_any_instance_of(Mechanize).to receive(:get) do |agent, url|
      requested << url
      html = if url.include?("SearchApplicationNotif") then notification_html
             elsif url.include?("id=") then details_html
             else
               lodged_html
             end
      Mechanize::Page.new(URI(url), { "content-type" => "text/html" }, html, 200, agent)
    end
    output = StringIO.new
    $stdout = output
    described_class.run
    output.string
  ensure
    $stdout = STDOUT
  end

  # The lodged fixture with only the given results, each repeated with a
  # reference of its own, and a matching count
  def page_with(results)
    doc = Nokogiri::HTML(lodged)
    originals = doc.css("div.result").to_a
    list = doc.at("#hiddenresult")
    originals.each(&:remove)
    results.each do |index, times|
      times.times do |copy|
        result = list.add_child(originals[index].dup)
        link = result.at("a.search")
        link.content = "#{link.text}-#{copy}" unless link.text.empty?
      end
    end
    doc.at("strong").content = results.sum { |_, times| times }.to_s
    doc.to_html
  end

  def record(reference)
    saved.reverse.find { |r| r["council_reference"] == reference }
  end

  describe "a complete application" do
    it "is saved with its address, description and details page" do
      run_with
      expect(record("CAR26/9001")).to eq(
        "council_reference" => "CAR26/9001",
        "address" => "1 Example Street NORTH WARD QLD 4810",
        "description" => "Referral Agency Response - Building Act - Carport within Front Setback",
        "info_url" => "https://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx?id=9000001",
        "date_scraped" => Date.today.to_s,
        "date_received" => "2026-10-01"
      )
    end

    it "uses the first address when there are several" do
      run_with
      expect(record("MCU26/9002")["address"]).to eq("2 Example Road PINNACLES QLD 4815")
    end
  end

  describe "an application missing something PlanningAlerts can do without" do
    it "is described as a Development Application when there is no description" do
      run_with
      expect(record("OPW26/9003")["description"]).to eq("Development Application")
    end

    it "links to the search page when there is no details link" do
      run_with
      expect(record("RAL26/9004")["info_url"])
        .to eq("https://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx")
    end

    it "leaves out date_received with a warning when the lodged date can't be read" do
      output = run_with
      expect(record("DBW26/9005")).not_to have_key("date_received")
      expect(output).to include("Warning: DBW26/9005 has an unreadable lodged date \"\"")
    end
  end

  describe "an application with no application number or address" do
    it "is skipped and reported, and counted in the total" do
      output = run_with
      expect(saved.map { |r| r["council_reference"] })
        .to eq(%w[CAR26/9001 MCU26/9002 OPW26/9003 RAL26/9004 DBW26/9005 MCU26/9011])
      expect(output).to include("Skipping bad application (thisweek result 6): POS26/9006 has no address")
      expect(output).to include("Skipping bad application (thisweek result 7): no application number")
      expect(output).to include("Finished - saved 6 records, skipped 2 bad applications")
    end

    it "is allowed up to 10 + 20% of the saved records" do
      expect { run_with(lodged_html: page_with([[0, 1], [5, 9]])) }.not_to raise_error
    end

    it "stops the run once there are more than 10 + 20% of the saved records" do
      expect { run_with(lodged_html: page_with([[0, 5], [5, 12]])) }
        .to raise_error(RuntimeError, "Too many bad applications: skipped 12, saved 5")
    end
  end

  describe "an application on public notification" do
    it "is saved with the notification dates from its details page" do
      run_with
      expect(requested).to include("https://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx?id=9000011")
      expect(record("MCU26/9011")).to include(
        "address" => "11 Example Street CURRAJONG QLD 4812",
        "description" => "Impact Assessable - Multiple Dwelling - 3 Units",
        "date_received" => "2026-09-09",
        "on_notice_from" => "2026-10-23",
        "on_notice_to" => "2026-11-13"
      )
    end

    it "is saved with a warning when its details page has no notification dates" do
      html = details.sub("Start Date of Notification", "Something else").sub("End Date of Notification", "Other")
      output = run_with(details_html: html)
      expect(record("MCU26/9011")).not_to include("on_notice_from", "on_notice_to")
      expect(output).to include("Warning: MCU26/9011 has an unreadable notification start date nil")
    end

    it "doesn't fetch a details page when there is no details link" do
      html = notification.sub(%r{\.\./\.\./Pages/XC\.Track/SearchApplication\.aspx\?id=9000011}, "")
      run_with(notification_html: html)
      expect(requested.grep(/id=/)).to be_empty
      expect(record("MCU26/9011")).not_to include("on_notice_from")
    end

    it "is counted once in the total when it is also in a lodged list" do
      output = run_with(notification_html: notification.gsub("MCU26/9011", "CAR26/9001"))
      expect(record("CAR26/9001")).to include("on_notice_from" => "2026-10-23")
      expect(output).to include("Finished - saved 5 records, skipped 2 bad applications")
    end

    it "stops when the details page has no history" do
      expect { run_with(details_html: details.sub('id="events"', 'id="other"')) }
        .to raise_error(RuntimeError, /No history found at .*id=9000011/)
    end
  end

  describe "checks on the page" do
    it "stops when the number of results doesn't match the stated count" do
      html = lodged.sub("<strong>7</strong>", "<strong>8</strong>")
      expect { run_with(lodged_html: html) }.to raise_error(RuntimeError, /Expected 8 applications but found 7/)
    end

    it "stops when there are applications but no results summary" do
      html = lodged.sub("applications found", "something else")
      expect { run_with(lodged_html: html) }.to raise_error(RuntimeError, /No results summary found/)
    end

    it "stops when the page states applications but none are found" do
      html = page_with([]).sub("<strong>0</strong>", "<strong>3</strong>")
      expect { run_with(lodged_html: html) }.to raise_error(RuntimeError, /Expected 3 applications but found 0/)
    end
  end

  describe "lists with no applications" do
    it "finish normally when the page says 0 applications found" do
      output = run_with(lodged_html: page_with([]), notification_html: page_with([]))
      expect(saved).to be_empty
      expect(output).to include("No applications lodged thisweek")
      expect(output).to include("No applications on public notification")
      expect(output).to include("Finished - saved 0 records")
    end

    # The empty page hasn't been seen yet, so it may word or leave out the count
    it "finish normally when the page gives no count" do
      html = page_with([]).sub("applications found", "something else")
      expect { run_with(lodged_html: html) }.not_to raise_error
    end
  end

  describe "periods" do
    it "scrapes this month and last month by default, then applications on notification" do
      run_with(period: "")
      expect(requested.map { |url| url[/d=(\w+)|Notif|id=/] }).to eq(%w[d=thismonth d=lastmonth Notif id=])
    end

    it "rejects an unknown MORPH_PERIOD" do
      expect { run_with(period: "fortnight") }.to raise_error(RuntimeError, /Unknown MORPH_PERIOD "fortnight"/)
    end
  end

  describe "MORPH_DEBUG" do
    around do |example|
      ENV["MORPH_DEBUG"] = "1"
      example.run
    ensure
      ENV.delete("MORPH_DEBUG")
    end

    it "prints each record as it is saved" do
      expect(run_with).to include('RECORD: {"council_reference"=>"CAR26/9001"')
    end
  end

  describe "the Australian proxy" do
    around do |example|
      ENV["MORPH_AUSTRALIAN_PROXY"] = "http://morph:example@proxy.example.org:8888"
      example.run
    ensure
      ENV.delete("MORPH_AUSTRALIAN_PROXY")
    end

    it "is used when MORPH_AUSTRALIAN_PROXY is set" do
      proxies = []
      allow_any_instance_of(Mechanize::HTTP::Agent).to receive(:set_proxy) { |_agent, proxy| proxies << proxy }
      expect(run_with).to include("Using Australian proxy...")
      # Mechanize.new calls set_proxy(nil) itself, so the scraper's call is the last
      expect(proxies.last).to eq("http://morph:example@proxy.example.org:8888")
    end
  end
end
