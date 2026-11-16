Grocy API doesn't use offset timezone info (chore execution gets the wrong time)
Forgive me if I've made an error, my python is rusty, but I've been 🕵️ [an issue with the Home Assistant custom component](https://github.com/custom-components/grocy/issues/252) which led me to changes in #250 which seem to result in the time zone offset being included in the API calls to Grocy (at least for `/chores/000/execute` which I was focusing on). According to [this issue](https://github.com/grocy/grocy/issues/1827) in the Grocy repo, the API calls will not parse time zone information so we shouldn't send it (the database [stores UTC](https://github.com/grocy/grocy/issues/214)).

**TL/DR**: I thought the changes in #250 broke the recording of the time when a chore is executed, but it seems it's been broken (in a different way) for a while now. The fix seems to be that `tracked time` *needs to be* in the format `YYYY-MM-DD hh:mm:ss` or Grocy's API will insert the current time (in GMT) instead, resulting in an offset time value (unless you're in GMT 😉).

### Observed behavior (debug level logging in Home Assistant):

With pygrocy **1.5.0** (and integration 4.7.1):
```
2022-09-23 11:19:44.032 DEBUG (SyncWorker_13) [pygrocy.grocy_api_client] --> POST /chores/25/execute
2022-09-23 11:19:44.033 DEBUG (SyncWorker_13) [pygrocy.grocy_api_client] {'tracked_time': '2022-09-23T11:17:35.185320-05:00', 'skipped': False, 'done_by': 3}
2022-09-23 11:19:44.033 DEBUG (SyncWorker_13) [pygrocy.grocy_api_client] <-- 200 for /chores/25/execute
2022-09-23 11:19:44.033 DEBUG (SyncWorker_13) [pygrocy.grocy_api_client] b'{"id":"90","chore_id":"25","tracked_time":"2022-09-23 16:19:44","done_by_user_id":"3","row_created_timestamp":"2022-09-23 11:19:44","undone":"0","undone_timestamp":null,"skipped":"0"}'
```

With pygrocy **1.4.1** (and integration 4.7.1):
```
2022-09-23 12:11:10.801 DEBUG (SyncWorker_10) [pygrocy.grocy_api_client] --> POST /chores/25/execute
2022-09-23 12:11:10.802 DEBUG (SyncWorker_10) [pygrocy.grocy_api_client] {'tracked_time': '2022-09-23T17:06:58.892222+00:00', 'skipped': False, 'done_by': 3}
2022-09-23 12:11:10.802 DEBUG (SyncWorker_10) [pygrocy.grocy_api_client] <-- 200 for /chores/25/execute
2022-09-23 12:11:10.802 DEBUG (SyncWorker_10) [pygrocy.grocy_api_client] b'{"id":"99","chore_id":"25","tracked_time":"2022-09-23 17:11:10","done_by_user_id":"3","row_created_timestamp":"2022-09-23 12:11:10","undone":"0","undone_timestamp":null,"skipped":"0"}'
```

### Observed behavior using the REST API browser within Grocy

Inspecting how the Grocy UI (web page) makes the call, I captured this post:
```
{ "tracked_time": "2022-09-23 14:18:16", "skipped": false }
```
To which the API then responds:
```
{"id":"105","chore_id":"26","tracked_time":"2022-09-23 14:18:16","done_by_user_id":"8","row_created_timestamp":"2022-09-23 14:18:15","undone":"0","undone_timestamp":null,"skipped":"0"}
```
This appears correct in the UI and the next chore execution appears to be correct as well.

If I send values for `tracked_time` that are not in `YYYY-MM-DD hh:mm:ss` format (for example using ISO8601-`YYYY-MM-DDThh:mm:ss.sss` or with any time zone offset, like `2022-09-23T20:23:16.033Z` or `2022-09-23T20:23:16.033+05:00`) Grocy will **ignore** the value and use the current time (GMT) for the `tracked_time` (same as if the `tracked_time` is omitted). This causes executions to appear at the incorrect time (and next due to be miscalculated) if you're not also in GMT.

We should be able to fix this by sending the *local time* in `YYYY-MM-DD hh:mm:ss` format to the API (at least for chore execution, not sure if it would apply to all API calls?).

cc: @marcelvriend (author of the PR)

### Additional contract requirements

- Add a public function `grocy_datetime_str(timestamp: datetime) -> str` in module `pygrocy.utils` that returns the datetime formatted as `YYYY-MM-DD HH:MM:SS`.
- Executing a chore sends the chore's `tracked_time` to the Grocy API as the local time formatted `YYYY-MM-DD HH:MM:SS`.
