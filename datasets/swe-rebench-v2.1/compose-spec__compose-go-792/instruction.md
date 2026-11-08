Provider services should make type a required attribute
https://github.com/compose-spec/compose-go/blob/e07723c227fee4a7063a55a0d072167679250116/schema/compose-spec.json#L392-L399

`type` should be a required attribute. Without it there is no way of knowing how to run the third-party component.
