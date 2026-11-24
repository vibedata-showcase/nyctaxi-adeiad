# NYC Taxi Analytics — Context

The vocabulary of the NYC taxi analytics data product: real TLC trip records, plus a simulated fleet operator and a simulated master-data platform.

**This file is the language layer, nothing else.** Layers and locations are in `repo-map.json`; columns and lineage are in the catalog; decisions are in `docs/adr/`.

## Language

**Trip**:
One completed taxi journey, as the TLC records it. A trip is identified by its natural columns: service type, vendor, pickup and dropoff time, pickup and dropoff zone, distance and total.

**Service type**:
Which fleet carried the trip: yellow (medallion taxis) or green (boro taxis). Green may not pick up in the Manhattan core or at the airports except by pre-arrangement, so airport volume is overwhelmingly yellow.
_Not_: vendor, because a vendor is the technology provider that supplies the meter and serves both fleets.

**Zone**:
A TLC taxi zone: the area a trip starts or ends in. Zones belong to a borough.

**Zone version**:
TLC re-designates zones, so a zone can have more than one version. The current version is the one in force now; a trip uses the version in force on its pickup date.

**Unresolved zone**:
A zone the TLC lists but cannot place in a borough. It is a real zone, so it joins like any other, and it pollutes a borough rollup unless the consumer filters it.

**Technology vendor**:
The provider that supplies a taxi's meter and sends its trip records. Vendors are renamed and acquired, so a vendor has a history.

**Fare component**:
One part of a trip's total: the fare itself, tip, tolls, taxes and surcharges.

**Fare residual**:
What is left of a trip's total after every modelled fare component. A non-zero residual means the total is not the sum of its parts.

**Billable trip**:
A trip whose total is positive. Revenue and flow reporting counts only billable trips inside the reporting window; quality reporting counts all trips and shows how many are billable.
_Not_: revenue trip, because whether a billable trip counts as revenue depends on how it was paid.

**Refund**:
A trip with a negative total.

**Zero-distance trip**:
A trip whose meter started and stopped in the same place.

**Trip quality verdict**:
A named condition a trip can meet, such as being a refund, being implausibly fast or touching an unresolved zone. Trips are flagged with their verdicts and never removed.

**Reporting window**:
The period the business reports on. Trips picked up inside it are in scope for revenue and flow reporting.
_Not_: a sampling window, because changing it changes the numbers, not the volume loaded.

**Payment method**:
How a passenger paid, such as by card or in cash. It decides whether a tip is recorded and whether a trip counts as revenue.

**No-charge and dispute payments**:
Payment methods under which a trip can carry a positive total yet is not revenue. They are not excluded from billable trips; each metric decides whether to count them.

**Measurable tip rate**:
The tip as a share of the fare, for payment methods that record tips only. For the others it is null.
_Not_: blended tip rate, because it falls in proportion to how much traffic pays another way and reads as a finding about a zone.

**Unmeasured tip**:
A tip the payment method does not record. It is not a zero tip.

**Fare regime**:
A set of surcharge rates with the dates they apply between.

**Daypart**:
A named band of the day, defined by the business. The lakehouse holds one row per hour, so the hour is its grain.

**Trip band**:
A range of distance, duration or fare used to profile trips.

**Origin-destination flow**:
The trips between one pickup zone and one dropoff zone.

**Published flow**:
An origin-destination pair with at least 25 billable trips in the reporting window, the population the origin-destination matrix reports (ADR 0017). Narrower than a flow: a pair below the floor exists in the trips but is not published.

**Borough crossing**:
A trip whose pickup and dropoff zones resolve to two different boroughs the TLC names. `EWR` is one of them; a trip that touches an unresolved zone is neither a crossing nor in-borough (ADR 0018).
_Not_: every trip between two different borough values, because two of those values are the absence of a borough.

**Unresolved group**:
The single group that zones the TLC cannot place in a borough report as, merging `Unknown` and `N/A`. It is published as a destination and an origin so its trips stay visible, and it stands outside the borough counts.

**Leaving-borough share**:
The share of a borough's trips, in a period, that end in a different borough. Its denominator is the borough's trips that resolved to a named borough at both ends, so the unresolved group is outside both the numerator and the denominator.

**Medallion**:
The licence to operate a taxi. It is transferable: the licence outlives the vehicle it currently covers and the driver who currently holds it, so it is neither of them.
_Not_: the bronze, silver and gold layering, which is a platform term defined elsewhere.

**Fleet attribution**:
A trip matched to one of the operator's vehicles and drivers. Most trips are not attributed, because the operator runs only part of the city's fleet.

**Garage**:
A depot where the operator keeps its vehicles.

**Shift**:
A driver's working period on one vehicle, from sign-on to sign-off. When no sign-off is recorded the shift is unclosed and ends at the operator's derived end, shortly after its last trip.

**Driver**:
A person who signs on to work a shift for the fleet operator. A driver is identified by the operator's own driver id, not by name or licence number.
_Not_: medallion holder, because a medallion is a licence to operate a taxi and its holder may drive none of the operator's shifts.

**Vehicle**:
A taxi the fleet operator runs. It is identified by the operator's own vehicle id, which stays with the vehicle across shifts and across a change of medallion.
_Not_: medallion, because the licence can move to another vehicle and one vehicle can be covered by more than one licence over its life.

**Lease type**:
How a driver pays for a vehicle: owner-operators share revenue, lease drivers pay a fixed rate.

**Status interval**:
The time between one driver status event and the next.

**Occupancy**:
The share of a driver's online time spent carrying a fare. It is collected from driver status events, separately from revenue.
_Not_: asset utilisation, because occupancy is measured against sign-on time and utilisation against the whole day.

**Locatable idle time**:
Time a driver spends waiting, with a place attached. It shows where a driver waited, where a trip shows where a driver earned.

**Online hour**:
An hour a driver is signed on. Driver performance is ranked on revenue per online hour.

**Asset utilisation**:
The share of the 24-hour day a vehicle is in use. A vehicle idle in the depot is an asset question; a driver idle on the road is a labour question.

**Date**:
A calendar day. Trips are reported on the day they started, and the same day means the same day in every document.

**Rate plan**:
How a trip is priced: metered, flat fare or negotiated.

**Maintenance event**:
One visit that takes a vehicle out of service, with the days lost and the cost. Availability is derived from these events, so the event is the record and the downtime is a measure.

**Maintenance downtime**:
Days a vehicle is out of service. They are removed from its availability, so a vehicle in the shop does not look idle.

**Week**:
A calendar week, starting on Monday.
