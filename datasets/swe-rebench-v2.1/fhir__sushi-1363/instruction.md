SUSHI should allow binding to Logical Models that have the #can-bind characteristic
Logical Models support specifing type characteristics through the `Characteristics` keyword. One of the values supported by this extension is `can-bind`, which states that the type can be bound to a terminology. SUSHI should allow Logical Models that have this characteristic specified to be used in bindings. If the characteristic is not specified, but the type is used in a binding, a warning should be logged (this should be similar to the behavior in SUSHI when a Logical Model is used as a reference without the `can-be-target` characteristic).

### Additional contract requirements

- When this warning is logged for a binding on `FutureResource.era`, its message must begin exactly with `Bindings can only be applied to logical model types with the #can-bind characteristic.` and include a later clause ending with `remove the binding from FutureResource.era.`
