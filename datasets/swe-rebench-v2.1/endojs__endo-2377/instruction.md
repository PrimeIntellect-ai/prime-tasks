import-bundle: allow symbol-named properties in inescapableGlobalProperties
## What is the Problem Being Solved?

As discussed in the comments on #1676, we'd like to convey `passStyleOf` into vat environments via a symbol-named property on the global, rather than a string-named property on VatData.

To support this, we need to change `import-bundle` to pay attention to symbol-named properties of `inescapableGlobalProperties`, because currently it uses `Object.keys`, which ignores symbols and only copies the string-named properties into the child Compartment's global. [HIDDEN]

While we're at it, we'll change `import-bundle` to look for *all* own properties of `inescapableGlobalProperties`, not just the enumerable ones (which matches the change from `Object.keys` to `Reflect.ownKeys`).

## Description of the Design

Add tests. [HIDDEN]

## Security Considerations

None I can think of, whoever is calling `importBundle` is in control of what properties they put on `inescapableGlobalProperties`, so if they want to make those properties unenumerable or Symbols, that's their business. And that party is in complete control over the guest/Compartment code's world.

## Scaling Considerations

none

## Test Plan

unit tests

## Compatibility Considerations

In the unlikely event that someone was already using Symbol-named properties, or unenumerable ones, in their `inescapableGlobalProperties` call, their guest code will start getting access to new properties, perhaps suprisingly. But that seems quite unlikely.


## Upgrade Considerations

To benefit from this, the host code must start using a new version of `import-bundle`. For the Agoric chain, that means a new version of `swingset-xsnap-supervisor`, so the process is:

* do a chain-halting upgrade that includes the new supervisor
* create a new vat, or upgrade an existing vat, both of which will then use the new supervisor code
* (also use a new liveslots, to get the `passStyleOf` endowment, and a new/current `@endo/pass-style`, which pulls that endowment)

### Additional contract requirements

- Copy symbol-keyed own properties of `inescapableGlobalProperties` onto the child Compartment global, preserving their values.
- Copy non-enumerable own properties of `inescapableGlobalProperties` onto the child Compartment global, preserving their values.
