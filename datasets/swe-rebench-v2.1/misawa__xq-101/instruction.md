strftime / strflocaltime / todateiso8601 / todate after strptime does not work
jq supports using strftime/strflocaltime/todateiso8601/todate  against the output of strptime.
```sh
❯ jq 'strptime("%F %T") | strftime("%Y %m %d %H %M %S")' <<< '"2022-03-01 12:10:20"'
"2022 03 01 12 10 20"

❯ jq 'strptime("%F %T") | todateiso8601' <<< '"2022-03-01 12:10:20"'
"2022-03-01T12:10:20Z"

❯ xq 'strptime("%F %T") | strftime("%Y %m %d %H %M %S")' <<< '"2022-03-01 12:10:20"'
Error: InvalidArgType("strftime", [2022, 2, 1, 12, 10, 20, 2, 59])

❯ xq 'strptime("%F %T") | todateiso8601' <<< '"2022-03-01 12:10:20"'
Error: InvalidArgType("strftime", [2022, 2, 1, 12, 10, 20, 2, 59])

❯ xq --version
xq 0.2.10-ad33a92d252fc4842f10730973e16f5da8434035
```

### Additional contract requirements

`strptime` output (the broken-down time array) must be accepted by `strftime`, `strflocaltime`, `todateiso8601`, and `todate`. For example:

```sh
❯ jq 'strptime("%FT%TZ") | strflocaltime("%Y-%m-%dT%H:%M:%S")' <<< '"2015-03-05T23:51:47Z"'
"2015-03-05T23:51:47"

❯ jq 'strptime("%FT%TZ") | todateiso8601' <<< '"2015-03-05T23:51:47Z"'
"2015-03-05T23:51:47Z"

❯ jq 'strptime("%FT%TZ") | todate' <<< '"2015-03-05T23:51:47Z"'
"2015-03-05T23:51:47Z"
```
