# Southern parcel network safety export, programme planning

Five files from the safety team's share, pulled for the 2025 programme.

## incidents.csv

The incident log for 2020 to 2024, one row per logged incident: `incident_id`, `depot`, `site`,
`date` and `severity`, which is `severe` for an injury that needed treatment away from the depot
and `minor` for everything else, first-aid cases, slips, near misses with a vehicle. Minor
incidents are entered by the depot itself, on the wall book or the depot's own app depending on
the depot. Severe incidents are entered by the regional safety lead, who is called for every one.
Every row in the file is dated inside the years the policy names.

`depot` is the depot the injured person is on the books of: the book the entry goes in is their
own depot's, and the regional lead files a severe incident under the person's cost centre,
because that is the cost centre the insurer's claim is opened against. `site` is the depot where
it happened. On most rows the two are the same. They differ when somebody is hurt away from their
own depot, and that is mostly trunk drivers: four of our depots are hubs, D136, D148, D030 and
D110, and through the night a hub's yard is largely drivers from the depot that runs the trunk
routes into it, D022, D078, D059 and D068 in turn, so between a third and a half of what is
logged at a hub went into the trunking depot's book. Any depot sees the odd visitor from
elsewhere in its region. The handsets the programme year runs on belong to the site, so from
January an incident is logged at the depot where it happened.

## insurer_claims.csv

The employer's liability insurer's claims file for the same years: `claim_id`, `depot`,
`claim_opened` and `incident_date`. The insurer opens a claim on every treated injury, against
the cost centre of the person hurt, so `depot` here is the log's `depot` column, the injured
person's own depot, and the file says nothing about where it happened. There is one row here for
every severe incident in the log and nothing in it the log does not already carry. It is here
because the safety team keeps the two side by side as a cross-check, not because anything needs
reading out of it.

## depots.csv

The depot register: `depot`, `region`, `merged_into`, then `labour_hours_<year>`, the hours
payroll reports for the depot's own staff, and `agency_hours_<year>`, the hours the agencies
invoiced for agency staff at that depot, each for every year of the log and for 2025, the
programme year, where both are budgeted. The hours a depot works are the two added together,
and a rate per hour is per hour worked whoever pays the wages. `depot` is the register's own id
for the yard. An id is letters, digits and hyphens; each network in the group numbers its yards
its own way, so an id is not a fixed width and a register's ids are not all the same length.
Ours are four characters throughout. Most of our depots run a quarter or less of their hours on
agency staff, four run a third or more.

`merged_into` is blank except on a depot that was folded into another depot during the log. Three
of ours were folded straight into a depot that stands on its own, D067 into D033, D084 into D044
and D152 into D039, all in January 2021. The rest of them are the old cluster: eleven yards we
closed into one another in the same reorganisation, each one folded into the next one along, the
work ending up at D108. Every one of those rows names the yard it went to, and that yard's row
names the next one, down to the one left standing. From the merge the log carries the surviving
depot's id for the absorbed site, in the `depot` column and the `site` column both, and the
programme year will too, but payroll kept every old cost centre, so a merged depot's hours are
still on its own row for every year, 2025 included. The rows of a cluster are one depot: the hours
on all of them and the incidents under all of those ids belong to the yard left standing at the
end, not to whichever yard sits between it and the row in the register, and a merged id itself
isn't a depot any more. So a reader who wants a depot's true hours and incidents has to follow
`merged_into` all the way to the id that is left standing, not stop at the first hop.

## pilot_year.csv

Sixty depots took the handsets a year before the rest of the network, and for that year they ran
them alongside the wall book. This file carries what the handsets counted at each of them:
`depot`, the `year`, the `incidents` counted and the `labour_hours` the depot worked, payroll and
agency together. The count is everything that happened at that depot that year, minor incidents
included, whoever was hurt and whichever depot's books they were on. What went into the log for
the same depots is still only what somebody wrote in a book, so the two do not match, and the gap
between them is different at every depot. It is the run that told the safety team the book was
short, and it is the one place in the export where what a depot logged and what actually happened
sit side by side, so a reading of the log can be checked against it. The pilot ran at ordinary
depots; the hubs went on the handsets with the rest of the network.

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

The safety league table ranks every depot by the logged incidents on its books per ten thousand
hours worked over the five years of the log. The memo proposes the top thirty for the programme,
and those are the depots in `league_table_top`. From January the network moves to mandatory
logging on the handsets, with every incident, minor or severe, entered at the depot where it
happened before the shift closes.

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
mattering, because everything goes through the handsets.

When the safety team puts a number on a depot it uses the severe incidents and nothing else. It
counts the severe rows in the log at the site they happened at, every year of the log together as
one count rather than a count a year, over the hours that depot worked across those same years,
payroll and agency, with the merged rows folded in first. That is the depot's rate, and the team
works it out the same way for every depot in the register, the pilot sixty included. It does not
scale the severe count up into a total by putting a figure on the severe share: the share is the
same everywhere, so it cancels out of a comparison between depots. It takes the counts as they
stand, with no allowance made for a small depot's thin year. The programme year runs at that same
rate, on the hours the register budgets for it.

The pilot file is where a reading gets checked, not where it comes from. A reading that measures
the depot rather than its paperwork puts the pilot depots in very nearly the order the handsets
put them in over the pilot year. The league table's own figure does not come close.
