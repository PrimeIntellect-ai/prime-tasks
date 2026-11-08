Update `contractAt` signature for artifacts
To bring `contractAt` inline with other optional artifact signatures, we should change the signature to:

```ts
m.contractAt(name, artifact, address)
```

Effectively swapping the position of artifact and address.

### Additional contract requirements

When using the artifact form `m.contractAt(name, artifact, address)` and the `address` argument is not one of the accepted types (a string, an `AddressResolvableFuture`, or a `ModuleParameterRuntimeValue<string>`), `contractAt` must throw an error whose message is:

`Invalid parameter "address" provided to contractAt "<name>" in module "<moduleId>"`

where `<name>` is the contract name passed to `contractAt` and `<moduleId>` is the id of the enclosing module.
