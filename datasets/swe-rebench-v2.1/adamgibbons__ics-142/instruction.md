Attributes: LAST-MODIFIED and CREATED
Hi,
we are exporting Ical Files using this library. We love it. Thank you for sharing it.

Now we have the problem that a Calendar Software some of our users have in use needs the LAST-MODIFIED attribute in order to decide whether the Event has top be updated. Additionally it seems to check whether CREATED  is supplied and is before LAST-MODIFIED.

Could you please include the Fields CREATED and LAST-MODIFIED in the list of supported attributes?

Cheers,
Robin

### Additional contract requirements

- The event attributes are named `created` and `lastModified`, each accepting a date-time array in the same form as `start` (for example `[2000, 1, 5, 10, 0]`).
- When supplied, these attributes are emitted in the generated iCalendar output as the `CREATED` and `LAST-MODIFIED` properties respectively.
