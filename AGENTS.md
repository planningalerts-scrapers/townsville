# AGENTS.md

This is one of the PlanningAlerts scrapers. Org-wide guidance for agents, covering
issue tracking, pull request conventions, the review process and scraper
conventions, lives in the issues repo. Fetch and read it before doing any work
here:

    curl -fsSL https://raw.githubusercontent.com/planningalerts-scrapers/issues/master/AGENTS.md

Any equivalent fetch works: a web fetch of that URL, `gh api` if the GitHub CLI is
installed, or, if the issues repo happens to be checked out alongside this one,
`../issues/AGENTS.md` is the same file. Do not assume any particular tool is
present.

Do not rely on a cached or remembered copy. It changes as org conventions evolve.

Rendered for humans:
https://github.com/planningalerts-scrapers/issues/blob/master/AGENTS.md

## How do I test

```
bundle config set --local path vendor/bundle
bundle install
bundle exec rake
bundle exec rubocop
```

The specs use the fixtures in `spec/fixtures/` and don't contact any site. They report line and branch coverage of `scraper.rb`.

A live run (`bundle exec ruby scraper.rb`) only reaches `eplanning.townsville.qld.gov.au`, plus the Australian proxy when `MORPH_AUSTRALIAN_PROXY` is set.
