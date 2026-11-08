Missing AWS::Route53::* types
## Hello!
<!-- Please leave this section as-is, it's designed to help others in the community know how to interact with our GitHub issues. -->

- Vote on this issue by adding a 👍 reaction
- If you want to implement this feature, comment to let us know (we'll work with you on design, scheduling, etc.)

## Issue details

<!-- Enhancement requests are most helpful when they describe the problem you're having as well as articulating the potential solution you'd like to see built. -->

```[tasklist]
### Tasks
- [ ] AWS::Route53::RecordSet
```

No L2s yet so don't need to map
```
- [ ] AWS::Route53::RecordSetGroup
```

### Affected area/feature

<!-- If you know the specific area where this feature request would go (e.g. Automation API, the Pulumi Service, the Terraform bridge, etc.), feel free to put that area here.  -->

### Additional contract requirements

Support mapping the CloudFormation resource type `AWS::Route53::RecordSet` to a Pulumi `aws:route53/record:Record` resource. The CloudFormation record properties are translated to the Pulumi resource arguments as follows:

- `HostedZoneId` becomes `zoneId`.
- `Name` becomes `name`.
- `Type` becomes `type`.
- `ResourceRecords` becomes `records`.
- `TTL` becomes `ttl`.
- `AliasTarget` becomes `aliases`, a single-element list whose `name` is the alias `DNSName`, whose `zoneId` is the alias `HostedZoneId`, and whose `evaluateTargetHealth` is the alias `EvaluateTargetHealth`.
- `HealthCheckId` becomes `healthCheckId`.
- `SetIdentifier` becomes `setIdentifier`.
- `CidrRoutingConfig` becomes `cidrRoutingPolicy`, with `collectionId` from `CollectionId` and `locationName` from `LocationName`.
- `Failover` becomes `failoverRoutingPolicies`, a single-element list whose `type` is the failover value.
- `Weight` becomes `weightedRoutingPolicies`, a single-element list whose `weight` is the weight value.
- `GeoProximityLocation` becomes `geoproximityRoutingPolicy`, with `bias`, `awsRegion`, `localZoneGroup`, and `coordinates` (a single-element list with `latitude` and `longitude`).
- `GeoLocation` becomes `geolocationRoutingPolicies`, a single-element list with `continent` from `ContinentCode`, `country` from `CountryCode`, and `subdivision` from `SubdivisionCode`.
- `MultiValueAnswer` becomes `multivalueAnswerRoutingPolicy`.

For records of type `TXT`, the record values are unquoted and split into one or more values, each at most 255 characters long, whose concatenation equals the original value.

The mapping accepts optional Pulumi resource options and passes them to the created resource.

When creating the mapped resource, use the CloudFormation logical ID as its Pulumi resource name.
