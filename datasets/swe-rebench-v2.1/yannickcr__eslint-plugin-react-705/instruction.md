react/jsx-handler-names should not trigger on "only"
The rule was triggered for a property `only`. I assume it checks for any prop key starting with `on`, but it would maybe make sense changing this to match `on[A-Z]` (i.e. camelcased keys) instead?

### Additional contract requirements

A prop is an event-handler prop only when its name begins with `on` followed by an uppercase letter. A non-handler value under `only` must not trigger the rule merely because the key starts with `on`.

A handler-named value supplied under a non-event prop (for example, `only={this.handleChange}`) must still be reported.
