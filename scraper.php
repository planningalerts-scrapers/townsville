<?php
require 'scraperwiki.php';

require 'scraperwiki/simple_html_dom.php';

// Townsville City Council Development Applications scraper
// (ICON Software Solutions PlanningXchange)
// Sourced from http://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx?ss=sq
// Formatted for http://www.planningalerts.org.au/

date_default_timezone_set('Australia/Sydney');

$date_format = 'Y-m-d';
$cookie_file = '/tmp/cookies.txt';
$comment_url = 'mailto:eplanning@townsville.qld.gov.au';
$terms_url = 'http://eplanning.townsville.qld.gov.au/Common/Common/Terms.aspx';
$rss_feed = 'http://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx?o=rss&d=last14days&t=PDMCUCode,PDMCUimp,PDOpWorks,PDReconfig';
$url_baselink = 'http://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx';

print "Scraping eplanning.townsville.qld.gov.au...\n";

//accept_terms($terms_url, $cookie_file);

// Download and parse RSS feed (last 14 days of applications)
$curl = curl_init($rss_feed);
curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
curl_setopt($curl, CURLOPT_USERAGENT, "Mozilla/5.0 (compatible; PlanningAlerts/0.1; +http://www.planningalerts.org.au/)");
$rss_response = curl_exec($curl);
curl_close($curl);

$rss_response = preg_replace('/utf-16/i', 'utf-8', $rss_response);
$rss = simplexml_load_string($rss_response);

// Iterate through each application
foreach ($rss->channel->item as $item)
{
    // RSS title appears to be the council reference
    $rss_title = explode('-', $item->title);
    $council_reference = trim($rss_title[0]);

    // RSS description appears to be the address followed by the actual description
    $rss_description = preg_split('/\./', $item->description, 2);
    // But of course some have no address, ugh...
    if(count($rss_description) != 2) {
        print "Description field missing an address for application $council_reference";
        continue;
    }
    $address = trim($rss_description[0]);
    $description = trim($rss_description[1]);

    $info_url = $url_baselink . trim((string)$item->link);

    //Publication date is a full ISO format string. eg. 2015-06-02T16:12:34.34+10:00
    //But we only want the date part.
    $date_scraped = date($date_format);
    $date_received = date($date_format, strtotime($item->pubDate));


    $application = array(
        'council_reference' => $council_reference,
        'address' => $address,
        'description' => $description,
        'info_url' => $info_url,
        'comment_url' => $comment_url,
        'date_scraped' => $date_scraped,
        'date_received' => $date_received
    );

    //Check to see if the record has already been inserted into the database.
    if (scraperwiki::get_var($council_reference) == "")
    {
      //No record found. Insert.
      print "New application found. Inserting ".$council_reference."\n";
      scraperwiki::save_sqlite(array('council_reference'), $application);
      scraperwiki::save_var($council_reference, $council_reference);
    }
    else
    {
      //Record is found, so skip.
      print "Record found. Skipping ".$council_reference."\n";
    }

}

function accept_terms($terms_url, $cookie_file)
{
    $curl = curl_init($terms_url);
    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($curl, CURLOPT_COOKIEJAR, $cookie_file);
    curl_setopt($curl, CURLOPT_COOKIEFILE, $cookie_file);
    $terms_response = curl_exec($curl);
    curl_close($curl);

    preg_match('/<input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="(.*)" \/>/', $terms_response, $viewstate_matches);
    $viewstate = $viewstate_matches[1];

    preg_match('/<input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="(.*)" \/>/', $terms_response, $eventvalidation_matches);
    $eventvalidation = $eventvalidation_matches[1];

    $postfields = array();
    $postfields['__VIEWSTATE'] = $viewstate;
    $postfields['__EVENTVALIDATION'] = $eventvalidation;
    $postfields['ctl00$ctMain1$BtnAgree'] = 'I Agree';
    $postfields['ctl00$ctMain1$chkAgree$ctl02'] = 'on';

    $curl = curl_init($terms_url);
    curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($curl, CURLOPT_POST, 1);
    curl_setopt($curl, CURLOPT_POSTFIELDS, $postfields);
    curl_setopt($curl, CURLOPT_COOKIEJAR, $cookie_file);
    curl_setopt($curl, CURLOPT_COOKIEFILE, $cookie_file);
    curl_exec($curl);
    curl_close($curl);
}
?>
