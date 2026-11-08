Logical/Resource root element cannot have empty/missing definition
For `Logical` and `Resource` entities only:

If the user does not provide a caret rule to set the root element's `short`/`definition`, the SUSHI will default the `short` to the specified `Title` and the `definition` to the specified `Description`.  In this case, if `Title` is not specified, then the root element will not have a `short`; and likewise, if `Description` is not specified, then the root element will not have a `definition`.

The problem is that [sdf-3](http://hl7.org/fhir/R4/structuredefinition.html#invs) states that _every_ element must have a `definition` -- so if SUSHI leaves it out, then the IG Publisher complains (rightfully so).  To avoid this, SUSHI should default the `short` and `definition` to the logical/resource _name_ when there otherwise would be no other value for them.

So...

Root element `short`:
* Use `^short` value if specified;
* Otherwise, use `Title:` value if specified;
* Otherwise, use name (specified after `Logical:` or `Resource:`)

Root element `definition`:
* Use `^definition` value if specified;
* Otherwise, use `Description:` value if specified;
* Otherwise, use the `short` value (following logic above, if necessary)
