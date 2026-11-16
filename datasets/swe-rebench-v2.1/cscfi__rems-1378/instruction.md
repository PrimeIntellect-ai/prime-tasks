"Change resources" does not update licenses
When making a new application, adding or deleting resources by "Change resources" does not update the licenses accordingly.

### Additional contract requirements

- The `:application.command/change-resources` command handler obtains the licences for the selected catalogue items from a `:get-licenses` function supplied in its injections map. `:get-licenses` takes the selected catalogue-item ids and returns a collection of licence maps, each containing at least an `:id`.
- The `:application.event/resources-changed` event carries, in addition to `:application/resources`, an `:application/licenses` field: a vector of maps each containing a `:license/id` (integer). The licence ids are the ids of the licences belonging to the selected catalogue items, as returned by `:get-licenses`.
- Applying an `:application.event/resources-changed` event to an application updates the application's `:application/licenses` to the licence ids carried by the event, each entry containing only `:license/id`.
