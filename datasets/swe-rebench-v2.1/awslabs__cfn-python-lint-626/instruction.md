W1001 incorrectly checking logic
`cfn-lint 0.13.0`

I'm receiving the following error:
```
W1001 Ref to resource "NatA" that many not be available when when condition "DeployNatGateway" is True and when condition "Az1Nat" is False at Resources/PrivateDefaultRouteA/Properties/NatGatewayId/Ref
```

W1001 is attempting to understand the logic of my Conditions but it's getting it wrong. For example, I have a VPC template that creates a NAT with the option of making it a single NAT or an HA NAT. So I have a parameter options that are
```
["None", "Single NAT", "High Availability"]
```

I then have the following conditions:
```
t.add_condition(
    "DeployNatGateway",
    Not(Equals(Ref(NatType), "None"))
)

t.add_condition(
    "Az1Nat",
    Or(
        Equals(Ref(NatType), "Single NAT"),
        Equals(Ref(NatType), "High Availability")
    )
)
```
I then have `NatA` being deployed with the condition `Az1Nat`. There is another resource, `PrivateDefaultRouteA` that has a `Condition` on `DeployNatGateway` and a `Ref` on `NatA`. It appears that since `PrivateDefaultRouteA` implicitly `DependsOn` `NatA` but are using different conditions, it thinks that they can conflict when they're actually two conditions based on the same parameter but we're using mutually exclusive options.

I'm not sure if this is a bug that should be fixed or if this is an example of an edge case that it's not going to handle. In the meantime, I would advocate that this is a good example to implement #113 because we don't want to completely disable W1001 as it did catch some logic errors that are valid.

### Additional contract requirements

- The parsed template exposes a conditions object (available as `cfn.conditions`). It has a public attribute `Parameters`: a dictionary whose keys are hash strings representing a `Ref` to a template parameter and whose values are that parameter's `AllowedValues` list. Parameters that do not declare `AllowedValues` are not included.
- The conditions object has a public method `get_scenarios(condition_names)` that returns the list of feasible truth-value combinations for the named conditions. When a condition compares a parameter reference (`Ref`) against a value, the parameter is only considered to take values from its `AllowedValues`, so combinations that require the parameter to take a value outside its `AllowedValues` are not returned.
- W1001 must not report a resource as unavailable when the referenced resource is available under every feasible combination of the conditions that apply to the reference. It must still report the warning when a feasible combination leaves the referenced resource unavailable.
