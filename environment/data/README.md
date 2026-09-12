# Southern parcel network safety export, programme planning

Five files from the safety team's share, pulled for the 2025 programme.

## incidents.csv

The incident log for 2020 to 2024, one row per logged incident: `incident_id`, `depot`, `date`
and `severity`, which is `severe` for an injury that needed treatment away from the depot and
`minor` for everything else, first-aid cases, slips, near misses with a vehicle. Minor incidents
are entered by the depot itself, on the wall book or the app depending on the depot. Severe
incidents are entered by the regional safety lead, who is called for every one.

## insurer_claims.csv

The employer's liability insurer's claims file for the same years: `claim_id`, `depot`,
`claim_opened` and `incident_date`. The insurer opens a claim on every treated injury, so there
is one row here for every severe incident in the log and nothing in it the log does not already
carry. It is here because the safety team keeps the two side by side as a cross-check, not
because anything needs reading out of it.

## depots.csv

The depot register: `depot`, `region`, `merged_into`, then `labour_hours_<year>`, the hours
payroll reports for the depot's own staff, and `agency_hours_<year>`, the hours the agencies
invoiced for agency staff at that depot, each for every year of the log and for 2025, the
programme year, where both are budgeted. The hours a depot works are the two added together, and
a rate per hour is per hour worked whoever pays the wages. Most of our depots run a quarter or less
of their hours on agency staff, four run a third or more.

`merged_into` is blank except on a depot that was folded into another depot during the log. Two of
ours were, D071 into D040 and D135 into D034, both in January 2021. From the merge the log carries
the site's incidents under the surviving depot's id, and the programme year will too, but payroll
kept the old cost centre, so the merged depot's hours are still on its own row for every year,
2025 included. The two rows are one depot: the hours on both rows and the incidents under both ids
belong to the survivor, and the merged id itself isn't a depot any more.

## pilot_year.csv

Sixty depots took the app a year before the rest of the network, and for that year they ran it
alongside the wall book. This file carries what the app counted for each of them: `depot`, the
`year`, the `incidents` the app counted and the `labour_hours` they worked, payroll and agency
together. The app total is
everything that happened at that depot that year, minor incidents included. What went into the
log for the same depots is still only what somebody wrote in the book, so the two do not match,
and the gap between them is different at every depot. It is the run that told the safety team the
book was short, and it is the one place in the export where what a depot logged and what actually
happened sit side by side, so a reading of the log can be checked against it.

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
over the five years of the log. The memo proposes the top thirty for the programme, and those
are the depots in `league_table_top`. From January the network moves to mandatory logging on
the app, with every incident, minor or severe, entered before the shift closes.

How the log is built matters for reading it. The same share of incidents are severe at every
depot, whatever its size or its habits, and every severe incident is logged, because the
regional lead is called out and the insurer opens a claim on each one. Minor incidents are
logged at whatever rate that depot's staff log them, which the safety team knows ranges from
nearly always at the app depots to hardly ever at some of the wall-book depots. Nobody has
reconciled the league table against that.

A depot's rate of incidents doesn't change from one year to the next. Sites change slowly and the
work is the same work, and when the safety team has gone back over the numbers the underlying
rate has come out flat year after year. The programme year runs at that same rate. What differs,
and differs by a lot, is how much of it each depot writes down, and from January that stops
mattering, because everything goes through the app.
