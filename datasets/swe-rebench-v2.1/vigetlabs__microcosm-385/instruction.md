Default options for effects and domains
On Microcosm, we have the ability to set default options:

```
class Repo extends Microcosm {
  static defaults {
    debug: true,
    maxHistory: 20
  }
}
```

We should do this for domains and effects. Additionally -- what if we allowed the configuration to cascade?

### Additional contract requirements

- A domain or effect may define a static `defaults` object whose properties are used as default setup options.
- `repo.addDomain(key, DomainClass, options?)` registers a domain and immediately calls its `setup(repo, resolvedOptions)` method.
- `repo.addEffect(EffectClass, options?)` registers an effect and immediately calls its `setup(repo, resolvedOptions)` method.
- The resolved options passed to `setup` are merged so that later sources override earlier ones, in this order: the Microcosm class's static `defaults`, the options passed to the Microcosm constructor, the domain's or effect's static `defaults`, and the options passed to `addDomain`/`addEffect`.
