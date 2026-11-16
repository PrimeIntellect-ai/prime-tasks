Dependencies & rest-dsl traits are never enabled
Follow up investigation to my [observation](https://github.com/apache/camel-k/pull/805#discussion_r300453032) in #805.

The cause of the problem is that the dependencies trait is never enabled. It checks for [HIDDEN], but since daf9c0fa003a80f69bbae3724fee8e642f2a20e4, the initial phase seen by the trait is [HIDDEN].

The same issue is true for the rest-dsl trait.

### Additional contract requirements

- The dependencies trait must remain disabled when the integration phase is empty.
- The dependencies trait must be enabled during the Initialization phase so its normal dependency processing can run.
- The rest-dsl trait must be enabled during the Initialization phase when its existing non-phase applicability conditions are met.
