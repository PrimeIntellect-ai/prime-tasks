Allow applications to specify which identifier to use
With trusted dealer the library currents forces the usage of incremental identifiers in the `[1, n]` range, which may be cumbersome if the application already has some form of identifier for participants.

Allow the caller to specify which identifier to use during key generation.

### Additional contract requirements

Trusted-dealer key generation must allow the caller to select participant identifiers rather than requiring the sequential identifiers. For valid caller-selected identifiers, the generated shares must be associated with those identifiers.

The trusted-dealer function `frost::keys::generate_with_dealer` takes the identifier choice as a third argument, placed before the random number generator, of type `frost::keys::IdentifierList<C>`:

- `IdentifierList::Default` assigns the identifiers 1 through `max_signers`.
- `IdentifierList::Custom(&[Identifier<C>])` assigns the given identifiers, one per participant; the returned share map is keyed by those identifiers.
