`example-value-or-externalValue` should only target OAS3
#882 puts under the light a minor issue: `value` or `externalValue` only make sense in the context of OAS3, but the rule `example-value-or-externalValue` apply to both OAS2 and OAS3.

#882 could be merged without incurring any breaking change. However, maybe should we rename the rule to `examples-value-or-externalValue` (and update the doco accordingly) to make it clear what it actually targets.
