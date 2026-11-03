# Townsville City Council scraper

This is a scraper that runs on [Morph](https://morph.io). To get started [see the documentation](https://morph.io/documentation).

It scrapes development applications for [Townsville City Council](https://www.townsville.qld.gov.au/) from the council's [ePlanning site](https://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx) and feeds [PlanningAlerts](https://www.planningalerts.org.au/authorities/townsville).

Issues with this authority are tracked in the shared issue tracker: [planningalerts-scrapers/issues#1460](https://github.com/planningalerts-scrapers/issues/issues/1460).

## How the site is structured

- The ePlanning site (XC.Track) lists every application lodged in a period (`thisweek`, `lastweek`, `thismonth` or `lastmonth`) on one page. The results are all in the page and paged in the browser with JavaScript. It covers development, building and plumbing applications, including referral agency responses (CAR) and changes to approvals.
- Each application is a `div.result` with the reference linking to its details page, the description, one or more addresses and a hidden "More" section with the lodged date and status. The scraper uses the first address.
- The page says how many applications it found. The scraper raises an error if the number of results doesn't match.
- A period with no applications, such as a quiet 1st of the month, is normal. The scraper prints `No applications lodged <period>` and carries on, even if the page gives no count. PlanningAlerts flags long gaps in new applications itself.
- Applications on public notification have their own list in the same format. Their notification start and end dates are read from each one's details page.
- The site's XML output (`o=xml`), used by the `multiple_icon` scraper, returns an error page, so this scraper reads the HTML. If another XC.Track council needs its HTML scraped too, this could become a `multiple_*` scraper.

## Running

```
bundle install
bundle exec ruby scraper.rb
```

To run the tests and style checks:

```
bundle exec rake
bundle exec rubocop
```

The tests use saved copies of the site's pages in `spec/fixtures/`, cut down to one result per case, with made-up references and addresses. They don't contact the council's site. A coverage summary is printed at the end, and the full report is written to `coverage/index.html`.

Environment variables:

- `MORPH_AUSTRALIAN_PROXY` - optional; when set (e.g. `http://morph:password@au.proxy.oaf.org.au:8888`) all requests go through the Australian proxy.
- `MORPH_PERIOD` - optional; one of `thisweek`, `lastweek`, `thismonth` or `lastmonth`. By default both `thismonth` and `lastmonth` are scraped. Applications on public notification are always scraped.
- `MORPH_DEBUG` - optional; when set, prints each record as it is saved.

Expected output is a heading for each list, a `Storing <reference> - <address>` line for each application, a count per list and a final total, for example:

```
Running ruby 3.2.2

Scraping applications lodged thismonth...
Storing CAR26/0574 - 40 Daintree Drive BUSHLAND BEACH QLD 4818
Storing CAR26/0575 - 21 Ranana Place MOUNT LOW QLD 4818
...
Storing POS26/0141 - 112 Gollogly Lane RASMUSSEN QLD 4815
Storing OPW25/0032.10 - 155 Lynam Road GUMLOW QLD 4815
Finished thismonth - processed 72 records

Scraping applications lodged lastmonth...
Storing CAR26/0508 - 6 Coleman Street HYDE PARK QLD 4812
Storing CAR26/0511 - 23 Crauford Street WEST END QLD 4810
...
Storing POS26/0128 - 16 Clayton Street HERMIT PARK QLD 4812
Storing RAL26/0108 - 10 Willeroo Court ANNANDALE QLD 4814
Finished lastmonth - processed 139 records

Scraping applications on public notification...
Storing MCU26/0034 - 128 Manton Quarry Road CALCIUM QLD 4816
Storing MCU26/0051 - 18 Hinchinbrook Drive THURINGOWA CENTRAL QLD 4817
...
Storing MCU26/0093 - 76 Gerard Street CURRAJONG QLD 4812
Storing MCU26/0112 - 11 Springfield Street YABULU QLD 4818
Finished on notification - processed 5 records

Finished - saved 213 records
```

A run takes under a minute (20 to 35 seconds on 31 October 2026).

An application with no application number or address is skipped with a `Skipping bad application` line, and the total then also says how many were skipped. Other gaps don't skip it. With no description it is described as "Development Application". With no details link it links to the search page. With an unreadable lodged or notification date, that date is left out and a warning is printed. The run stops with an error once more than 10 + 20% of the saved count have been skipped.

An application on public notification is often also in the lodged lists. Records are saved by `council_reference`, so the second save updates the same record and adds the notification dates. The final total counts each record once, so it can be less than the sum of the per-list counts (213 rather than 216 above). The total is usually a couple of hundred. The records are saved to `data.sqlite` in the working directory.
