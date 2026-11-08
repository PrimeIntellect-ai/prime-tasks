always_increment value ignored when calver_format specified
bump-my-version: 1.1.2
Python version: 3.12.3
Platform: Linux, x86_64

## Scenario
CalVer-based format, with a patch component which can be incremented even after the date has changed (e.g. to patch a maintained older release).

```toml
[tool.bumpversion]
current_version = "22.49.0"
parse = '''
(?x)
(?P<release>
    (?:\d{1,3})\.   # YY (year)
    (?:\d{1,2})     # WW (week)
)\.
(?P<patch>\d+)      # patch
'''
serialize = ["{release}.{patch}"]

[tool.bumpversion.parts.release]
calver_format = '{YY}.{WW}'
always_increment = false
```

## Expected behaviour
Explicitly setting `always_increment = false` for a part with `calver_format` set would override the [default CalVer behaviour of setting `always_increment` to `true`]((https://callowayproject.github.io/bump-my-version/howtos/calver/#expected-behavior)).

e.g. if we are in week 19 of 2025, expect:
```shell
$ bump-my-version show-bump
22.49.0 ── bump ─┬─ release ─ 25.19.0
                 ╰─ patch ─── 22.49.1
```

## Actual behaviour
`always_increment` setting is ignored:

```shell
$ bump-my-version show-bump
22.49.0 ── bump ─┬─ release ─ 25.19.0
                 ╰─ patch ─── 25.19.0
```

```shell
$ bump-my-version show
[...]
 'parts': {'patch': {'always_increment': False,
                     'calver_format': None,
                     'depends_on': None,
                     'first_value': None,
                     'independent': False,
                     'optional_value': None,
                     'values': None},
           'release': {'always_increment': True,   <------------------------- manual setting ignored
                       'calver_format': '{YY}.{WW}',
                       'depends_on': None,
                       'first_value': None,
                       'independent': False,
                       'optional_value': None,
                       'values': None}},
[...]
```
