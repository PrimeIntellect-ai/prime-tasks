Support overrides
When adding TypeScript support in `eslint-config-kentcdodds` (see https://github.com/kentcdodds/eslint-config-kentcdodds/pull/54), I noticed CI isn’t failing even though I haven't added all @typescript-eslint rules (yet).

I'm happy to help out if you could point me into the right direction of adding support here. 🙂

### Additional contract requirements

- When computing the set of available rules and the set of enabled rules for a configuration, the plugins and rules contributed by the configuration's `overrides` entries that apply to the files being analyzed must be included. Overrides that apply to different files are combined: a rule enabled by any applicable override counts as enabled, and a rule belonging to a plugin declared by any applicable override counts as an available rule. Consequently, a rule enabled by an applicable override must not be reported as unused, and a rule belonging to a plugin declared by an applicable override must be reported as unused when it is not enabled.
