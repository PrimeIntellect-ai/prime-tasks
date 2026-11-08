Propose new rule: no-tracked-properties-from-args
Disallow the creation of `@tracked value = this.args.someValue` as this will not get properly updated when the args change, which is unlikely to be what the developer wants.
