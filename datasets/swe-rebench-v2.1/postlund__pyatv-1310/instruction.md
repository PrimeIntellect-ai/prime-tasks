Enhance feature detection of play_url and improve error handling
### What feature would you like?

Feature availability of `play_url` is solely based on credentials being available or not. This is generally the case as credentials are needed for AirPlay on the Apple TV (which supports `play_url`) and not on the HomePod or other AirPlay receivers (which does *not*  support `play_url`). An edge case is older Apple TV devices with device verification turned off, where it will reported as unsupported even if is supported.

### Describe the solution you'd like

A better way is to check if `SupportsAirPlayVideoV1` or `SupportsAirPlayVideoV2` is present in the AirPlay feature flags.

An additional enhancement is to check availability of that feature in `play_url` and raise an exception in case it is not. This will make it more clear to users calling that function, expecting it to work on the HomePod. Preferably in the facade.

### Any other information to share?

This should be included in 0.9.0 as I find it important.
