shorthands: create a function for transition property
transition: ".3s cubic-bezier(.33,0,0,1) all" can't be used with griffel atm

### Additional contract requirements

- Expose the helper as `shorthands.transition` through Griffel's public API.
- The call `shorthands.transition('all', '.3s', '0s', 'cubic-bezier(.33,0,0,1)')` must produce a Griffel style object that preserves these values in its transition longhands: `transitionProperty` is `all`, `transitionDuration` is `.3s`, `transitionDelay` is `0s`, and `transitionTimingFunction` is `cubic-bezier(.33,0,0,1)`.
