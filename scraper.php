<?php
require_once 'vendor/autoload.php';
require_once 'vendor/openaustralia/scraperwiki/scraperwiki.php';

use PGuardiario\PGBrowser;
use Torann\DomParser\HtmlDom;

date_default_timezone_set('Australia/Sydney');

# Default to 'thisweek', use MORPH_PERIOD to change to 'thismonth' or 'lastmonth' for data recovery
switch(getenv('MORPH_PERIOD')) {
    case 'thismonth' :
        $period = 'thismonth';
        break;
    case 'lastmonth' :
        $period = 'lastmonth';
        break;
    default         :
        $period = 'thisweek';
        break;
}
print "Getting data for `" .$period. "`, changable via MORPH_PERIOD environment\n";

$comment_url = 'mailto:eplanning@townsville.qld.gov.au';
$url_base = 'http://eplanning.townsville.qld.gov.au/Pages/XC.Track/SearchApplication.aspx';
$url_query = 'k=LodgementDate&t=PDMCUCode,PDMCUimp,PDOpWorks,PDReconfig,QMCU,QRAL,QOPW,QDBW,QPOS,QEXC,QSPS,QCAR,PDSAMCUse,PDSARecon,PDSAOpWks';

$browser = new PGBrowser();
$full_url = $url_base. '?' .$url_query. '&d=' .$period;
$page = $browser->get($full_url);

$page_dom = HtmlDom::fromString($page->html);
$results = $page_dom->find("div[class=result]");

foreach ($results as $result) {
    $info_url = explode("?", $result->find('a',0)->href);
    $info_url = $url_base . '?' . $info_url[1];

    // getting detail page
    $page2 = $browser->get($info_url);
    $page2_dom = HtmlDom::fromString($page2->html);
    $divs = $page2_dom->find("div[class=detailleft]");

    foreach ($divs as $div) {
        switch ($div->plaintext) {
            case 'Description:' :
                $description = trim($div->nextSibling()->plaintext);
                break;
            case 'Properties:' :
                $address = explode("\n", $div->nextSibling()->plaintext);
                $address = trim(preg_replace('/\s+/', ' ', $address[0]));
                break;
            case 'Lodged:' :
                $date_received = explode("/", $div->nextSibling()->plaintext);
                $date_received = $date_received[2] . '-' . $date_received[1] . '-' . $date_received[0];
                break;
        }
    }

    $record = [
        'council_reference' => $result->find('a',0)->plaintext,
        'address' => $address,
        'description' => $description,
        'info_url' => $info_url,
        'comment_url' => $comment_url,
        'date_scraped' => date('Y-m-d'),
        'date_received' => $date_received
    ];

    # Check if record exist, if not, INSERT, else do nothing
    print ("Saving record " .$record['council_reference']. " - " .$record['address']. "\n");
//         print_r ($record);
    scraperwiki::save(['council_reference'], $record);
}
