Possible to set X-WR-CALNAME
Is it possible to set <code>X-WR-CALNAME</code>?
I cannot find anything about this value in the documentation.

Would be great to be able to set - otherwise the default value when subscribing to .ics is set to "Undefined".

Many thanks Kazuyuki

### Additional contract requirements

The public event input accepts an optional string field named `calName`. When supplied, event construction preserves its value as `event.calName`, and event validation accepts it and preserves it in the validated value.
