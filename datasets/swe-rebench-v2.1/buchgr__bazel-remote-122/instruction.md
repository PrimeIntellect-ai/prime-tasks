incorrect ActionResult validation
I recently added some ActionResult validation, including one check that seems to be technically incorrect but still useful in practice: zero-length serialized ActionResult messages are currently considered invalid.

This is technically incorrect, because an ActionResult might legitimately have no outputs apart from the exit code (and if that exit code is 0 then the serialized value could be zero-length). One possible use case for this is a sanity check.  But this is bad, because a zero-length file is perhaps the most common form of data corruption, and we have no way to recognise when this is corruption and when it is legitimate.

However in practice, there are many cases where this type of ActionResult can be reasonably be expected never to occur (eg when REAPI is only used for compilation jobs, like recc or goma jobs). And in that case, maybe it's worth keeping this validation, off by default and hidden by a command line flag. Would such a flag be welcome, or should I just remove this validation?
