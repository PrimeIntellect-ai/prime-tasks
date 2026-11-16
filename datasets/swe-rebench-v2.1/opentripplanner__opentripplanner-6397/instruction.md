SIRI references pointing to `ScheduledStopPoint` instead of `Quay`
### Background

South Tyrol in Italy has a SIRI feed where the `<StopPointRef>` elements point to `ScheduledStopPoint` and not `Quay`.

After a lot of [discussions with the NeTEx authors](https://public.3.basecamp.com/p/TcEEP5WrNZJPBxrJU9GAjint) as well as the Entur authors, we agreed that OTP should support `ScheduledStopPoint` references in SIRI as well as `Quay`.

### Design

To achieve this I propose the following design:

![ScheduledStopPoint-Page-1 drawio](https://github.com/user-attachments/assets/b7179b98-6403-46f8-b05d-a661c76dbcc2)

Here is a diagram showing the NeTEx data model and its closest equivalent in the OTP model.

![classmodel](https://github.com/user-attachments/assets/13938a81-005d-4c3b-8205-57adc11d3e0f)


Here are the key data flows:

- `TimetableRepository` will have a new map from `ScheduledStopPointId` to `QuayId`
- This collection is filled during the graph build
- `TimetableRepository` is then is then injected into `TransitService` which is injected into the SIRI updaters

cc @rcavaliere @t2gran

### Additional contract requirements

- Add a public method `addScheduledStopPointMapping(Map<FeedScopedId, RegularStop> mapping)` to `org.opentripplanner.transit.service.TimetableRepository` that stores the given mapping from ScheduledStopPoint ids to their `RegularStop`.
- Add a public method `findStopByScheduledStopPoint(FeedScopedId scheduledStopPoint)` to `org.opentripplanner.transit.service.TimetableRepository` returning `Optional<RegularStop>`: the associated stop if a mapping exists, otherwise an empty `Optional`.
- Add a public method `findStopByScheduledStopPoint(FeedScopedId scheduledStopPoint)` to the `org.opentripplanner.transit.service.TransitService` interface returning `Optional<RegularStop>`, exposing the lookup from `TimetableRepository`.
- Add a public method `resolveQuay(String stopPointRef)` to `org.opentripplanner.updater.siri.EntityResolver` returning `RegularStop`: if `stopPointRef` matches a ScheduledStopPoint mapping it resolves to the associated stop, otherwise it is treated as a quay id.
