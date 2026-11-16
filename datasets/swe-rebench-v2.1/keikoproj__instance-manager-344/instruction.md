Subnets field should deduplicate if duplicate values are provided
If someone mistakenly provides dupe values, e.g.:
```yaml
  subnets:
  - subnet-0310e3af3100225b9
  - subnet-0310e3af3100225b9
  - subnet-05c09777fce590171
```

The call will fail with:
```
"error": "provisioner eks reconcile failed: failed to update scaling group: ValidationError: Duplicate subnets specified: [subnet-0310e3af3100225b9]
```

We should consider having the controller dedupe values to avoid the error in this case and only use the two subnets.

Downside is that maybe we would like to explicitly provide this error if the user made a mistake and provided wrong subnets.
