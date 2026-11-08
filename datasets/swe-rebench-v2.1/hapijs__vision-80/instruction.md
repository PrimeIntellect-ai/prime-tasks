Register Helpers programmatically
Would be lovely if we could register helpers programmatically.

E.g. server.views.registerHelper('someHelper', function(){});

This would allow for simpler helper module sharing, rather than having to create a helper file for each helper in a bundle.

Perhaps this exists I just couldn't find a simple solution by reverse engineering.

### Additional contract requirements

Registering programmatic helpers must not cause rendering to fail when the configured template engine does not support helper registration.
