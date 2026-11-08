Add support to call a method after the mapping is completed
In order to call a method at the end of mapping a simple middleware could be added that can be constructed with a callback. This will enable users to easily decorate their existing software as middleware for JsonMapper.

Consider the call back being invoked at each mapping (recursive) or only when leaving the top-level mapping method.

Reference: https://github.com/cweiske/jsonmapper/issues/142

### Additional contract requirements

Provide the middleware as `JsonMapper\Middleware\FinalCallback`, constructed with the supplied callback. Invoke the callback after a mapping pass completes. For recursive mappings, support both scopes: by default invoke it only after the top-level mapping completes; when the optional second constructor argument is `false`, invoke it after every mapping pass, including recursive passes.
