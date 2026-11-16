Prevent "bad" router usages
I noticed some usage of `.lookup('router:main')` in our apps that I factored away. not sure if it's possible, but would be nice to have a lint rule against this. Also against `router._routerMicroLib` maybe?

### Additional contract requirements

- The `router:main` check is opt-in: the rule exposes a boolean option named `catchRouterMain` that defaults to `false`. The `.lookup('router:main')` usage is only reported when `catchRouterMain` is enabled; when the option is absent or `false`, such usage must not be reported.
- The private property targeted by the `catchRouterMicrolib` option is spelled `_routerMicrolib` (the exact Ember property name).
