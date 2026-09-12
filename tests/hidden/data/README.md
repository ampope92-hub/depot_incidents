# Northern parcel network safety export, programme planning

Five files from the safety team's share, pulled for the 2023 programme.

## incidents.csv

The incident log for 2018 to 2022, one row per logged incident: `incident_id`, `depot`, `date`
and `severity`, which is `severe` for an injury that needed treatment away from the depot and
`minor` for everything else, first-aid cases, slips, near misses with a vehicle. Minor incidents
are entered by the depot itself, on the wall book or the app depending on the depot. Severe
incidents are entered by the regional safety lead, who is called for every one.

## insurer_claims.csv

The employer's liability insurer's claims file for the same years: `claim_id`, `depot`,
`claim_opened` and `incident_date`. One claim per treated injury, so it holds a row for every
severe incident already in the log and nothing further. The team keeps it alongside as a
cross-check; the job doesn't need anything out of it.

## depots.csv

The depot register: `depot`, `region`, `merged_into`, then `labour_hours_<year>`, the hours
payroll reports for the depot's own staff, and `agency_hours_<year>`, the hours the agencies
invoiced for agency staff at that depot, each for every year of the log and for 2023, the
programme year, where both are budgeted. The hours a depot works are the two added together, and
a rate per hour is per hour worked whoever pays the wages. The big Northern hubs run on agency
labour: thirty depots take more than half their hours from the agencies, the rest a quarter or
less.

`merged_into` is blank except on a depot that was folded into another depot during the log. Fifteen
Northern depots were, all in January 2019, when the network took over the old regional carriers.
From the merge the log carries the site's incidents under the surviving depot's id, and the
programme year does too, but payroll kept the old cost centres, so a merged depot's hours are
still on its own row for every year, 2023 included. The two rows are one depot: the hours on both
rows and the incidents under both ids belong to the survivor, and the merged id itself isn't a
depot any more.

## pilot_year.csv

Sixty depots took the app a year before the rest of the network and ran it alongside the wall
book for that year. This file holds what the app counted for each of them: `depot`, the `year`,
the `incidents` the app counted and the `labour_hours` they worked, payroll and agency together.
The app total covers
everything that happened at the depot that year, minor incidents included. The log for the same
depots is still just what got written in the book, so it comes to less, and by a different amount
at each one. It is the run that showed the book was short, and the one place here where a depot's
log and what actually happened sit side by side, so a reading of the log can be checked on it.

## policy.json

| key | meaning |
|---|---|
| network | the network |
| log_years | the first and last year the log covers |
| programme_year | the year the programme runs |
| list_size | how many depots the programme can take |
| minimum_rate_ratio | the bar the list is held to, see instruction |
| league_table_top | the depots at the top of the memo's league table |

## From the memo

The safety league table ranks every depot by logged incidents per ten thousand hours worked
over the five years of the log. The memo proposes the top twenty for the programme, and those
are the depots in `league_table_top`. From January the network moves to mandatory logging on
the app, with every incident, minor or severe, entered before the shift closes.

How the log is built matters for reading it. The same share of incidents are severe at every
depot, whatever its size or its habits, and every severe incident is logged, because the
regional lead is called out and the insurer opens a claim on each one. Minor incidents are
logged at whatever rate that depot's staff log them, which the safety team knows ranges from
nearly always at the app depots to hardly ever at some of the wall-book depots. Nobody has
reconciled the league table against that.

What a depot runs at doesn't shift year on year. The sites and the work stay put, and every time
the safety team has gone back over it the underlying rate has come out flat, and the programme
year runs at that same rate. What differs, by a lot, is how much of it each depot gets into the
log, and from January that stops mattering, with everything going through the app.
