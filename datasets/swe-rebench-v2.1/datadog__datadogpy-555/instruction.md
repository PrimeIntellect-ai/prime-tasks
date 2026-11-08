String decode in dogwrap
**Describe the bug**
The parameters `notify_success`, `notify_warning` and `notify_error` cause the `AttributeError` shown below to be thrown when used.

```
Traceback (most recent call last):
  File "/usr/local/bin/dogwrap", line 8, in <module>
    sys.exit(main())
  File "/usr/local/lib/python3.7/site-packages/datadog/dogshell/wrap.py", line 377, in main
    event_body = build_event_body(cmd, returncode, stdout, stderr, notifications)
  File "/usr/local/lib/python3.7/site-packages/datadog/dogshell/wrap.py", line 209, in build_event_body
    notifications=notifications.decode("utf-8", "replace")
AttributeError: 'str' object has no attribute 'decode'
```

Line 209 attempts to call a decode method on a string. To my knowledge, this method has been removed in python3.

**To Reproduce**
Steps to reproduce the behavior:
1. Install datadog for python3
2. Execute the `dogwrap` command with the `--notify_error` flag set to any string and a command that causes an error
3. Get an exception

**Expected behavior**
The datadog event to be logged with the string specified by `--notify_error` in after `**>>>> NOTIFICATIONS <<<<**`

**Screenshots**
```
$ dogwrap -n "Example Error" -k ${API_KEY} --submit_mode errors --notify_error "test notification" "pwd -h"

Traceback (most recent call last):
  File "/usr/local/bin/dogwrap", line 8, in <module>
    sys.exit(main())
  File "/usr/local/lib/python3.7/site-packages/datadog/dogshell/wrap.py", line 377, in main
    event_body = build_event_body(cmd, returncode, stdout, stderr, notifications)
  File "/usr/local/lib/python3.7/site-packages/datadog/dogshell/wrap.py", line 209, in build_event_body
    notifications=notifications.decode("utf-8", "replace")
AttributeError: 'str' object has no attribute 'decode'
```

**Environment and Versions (please complete the following information):**
```
$ python3 --version
Python 3.7.6
$ dogwrap --version
dogwrap 0.34.1
```

### Additional contract requirements

- When notification data is provided as bytes, the event body must contain the notification text rather than a bytes representation, matching the body produced for the equivalent string input.
