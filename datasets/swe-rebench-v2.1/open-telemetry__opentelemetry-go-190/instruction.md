SDK ignores "FollowsFrom" relationships
[Currently](https://github.com/open-telemetry/opentelemetry-go/blob/384b4bb86af69eed21dc9e29579894576be9ce50/sdk/trace/tracer.go#L50), the SDK only propagates the parent through the context or if the provided reference is explicitly set to `ChildOfRelationshipType`. `FollowsFromRelationshipType` parents thus get ignored, which seems unexpected.
