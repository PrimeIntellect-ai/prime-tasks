Implement true constants.
True constants such as

- atmospheric pressure
- reference sound pressure p_0
- reference sound power W_0
- ...

can be implemented as global variables in the constants module.

### Additional contract requirements

Expose these values as module-level constants in `pyfar.constants`:

- `reference_atmospheric_pressure`: standard atmospheric pressure, `101325.0` Pa.
- `reference_sound_pressure`: reference sound pressure, `20e-6` Pa.
- `reference_sound_power`: reference sound power, `1e-12` W.
