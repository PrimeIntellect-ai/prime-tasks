CLI requires lat/lon in params for charging
@rikroe I ran into a problem with 16.1 CLI version, when trying to start/stop charging:

`bimmerconnected charge USERNAME PASSWORD rest_of_world VIN start`

`Traceback (most recent call last):
  File "C:\Users\jeter\AppData\Local\Programs\Python\Python310\lib\runpy.py", line 196, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "C:\Users\jeter\AppData\Local\Programs\Python\Python310\lib\runpy.py", line 86, in _run_code
    exec(code, run_globals)
  File "C:\Users\jeter\AppData\Local\Programs\Python\Python310\Scripts\bimmerconnected.exe\__main__.py", line 7, in <module>
  File "C:\Users\jeter\AppData\Local\Programs\Python\Python310\lib\site-packages\bimmer_connected\cli.py", line 334, in main
    if args.lat and args.lng:
AttributeError: 'Namespace' object has no attribute 'lat'`

I guess you need something like:
`if args.lat.exists()` in line 334 in cli.py?

_Originally posted by @jeterke in https://github.com/bimmerconnected/bimmer_connected/discussions/627#discussioncomment-10214331_

Issue after refactoring CLI. Testing/parsing `lat` and `lon` only needs to be done for specific parameters.

### Additional contract requirements

- `MyBMWAccount.set_observer_position(latitude: float, longitude: float) -> None` (in `bimmer_connected.account`) raises `ValueError` with a message containing `requires both 'latitude' and 'longitude' set` when either argument is `None`. On success it sets `account.config.observer_position` to a `GPSPosition` for the given coordinates, with the values stored as floats.
- `GPSPosition` (in `bimmer_connected.models`) raises `TypeError` with a message containing `GPSPosition requires either none or both arguments set` when exactly one of `latitude`/`longitude` is `None`. It accepts only numeric coordinates, requires latitude between -90 and 90 and longitude between -180 and 180 (raising `ValueError` otherwise), and stores supplied values as floats.
- The CLI must only read the `lat`/`lng` arguments for the commands that define them; a command that does not define them (for example `charge`) must run without accessing missing attributes.
