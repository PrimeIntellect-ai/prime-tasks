DateTime#toISO() of local time can result in invalid format (offset "-00:00")
I noticed a bug in our application only users in Portugal encountered when sending requests to our server containing ISO formatted dates. We were only able to reproduce it by setting our computer's time zones to GMT (e.g. "Europe/London").

The issue is that luxon (v 1.22.0) formats the current date as follows:

```js
> luxon.DateTime.local().toISO()
'2020-02-17T10:02:14.703-00:00'
```

According to the Wikipedia entry on ISO 8601:

> An offset of zero, in addition to having the special representation "Z", can also be stated numerically as "+00:00", "+0000", or "+00". However, **it is not permitted to state it numerically with a negative sign, as "−00:00", "−0000", or "−00"**. The section dictating sign usage (section 3.4.2 in the 2004 edition of the standard) states that a plus sign must be used for a positive or zero value, and a minus sign for a negative value. Contrary to this rule, RFC 3339, which is otherwise a profile of ISO 8601, permits the use of "-00", with the same denotation as "+00" but a differing connotation.[29]

Funny enough, the following works:

```js
> luxon.DateTime.local().setZone(luxon.DateTime.local().zoneName).toISO()
'2020-02-17T10:08:04.416+00:00'
```
(Note: this does not work around the problem if a `Zone` object is given to `setZone`, it only works for the zone name, i.e. `Europe/London`)

As this shows there is a workaround that we will include in our application to fix the issue for our British and Portuguese users.

Since I'm not familiar with the luxon code base, I have not yet started working on a fix/PR. Please tell me whether this seems like an easy fix and you'll be able to do it. Otherwise please point me in some direction and I'll see what I can come up with.

### Additional contract requirements

- `DateTime#toISO()` on a local DateTime whose offset is zero must show the offset as `+00:00`, never `-00:00`. Numeric offsets use `+` for zero or positive offsets and `-` for negative offsets.
