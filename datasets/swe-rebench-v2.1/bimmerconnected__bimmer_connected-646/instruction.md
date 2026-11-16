Update overver position checks
The observer position wasn't being set in my version (`bimmer-connected==0.16.0.0b2`). After adding it, the guard fails if 0.0 is used :):
```
    if args.lat and args.lng:
        account.set_observer_position(args.lat, args.lng)
```

_Originally posted by @sshaikh in https://github.com/bimmerconnected/bimmer_connected/discussions/631#discussioncomment-10168095_

Maybe take inspiration from https://github.com/home-assistant/core/blob/dff964582bb52882805b50a5f5bd235aab35e20b/homeassistant/helpers/config_validation.py#L136-L142.

### Additional contract requirements

- Add a public class `GPSPosition` in module `bimmer_connected.models` with a constructor `GPSPosition(latitude, longitude)` that stores the two coordinates.
- A coordinate of `0.0` is a valid position and must not be treated as absent.
- The valid ranges are inclusive: latitude from `-90` to `90`, longitude from `-180` to `180`.
- Constructing a `GPSPosition` with a supplied coordinate that is not an `int` or `float` raises `TypeError`.
- Constructing a `GPSPosition` with a latitude outside `-90`..`90` or a longitude outside `-180`..`180` raises `ValueError`.
- Constructing a `GPSPosition` with exactly one of the two coordinates set to `None` raises `TypeError`.
