Make TraitListEvent arguments keyword-only
TraitsUI has some broken uses of `TraitListEvent` where arguments are passed in the wrong order. To avoid this problem, it would make sense to make the `TraitListEvent` arguments keyword-only.

We can't do this until TraitsUI fixes its uses, however.

Ref: enthought/traitsui#791
