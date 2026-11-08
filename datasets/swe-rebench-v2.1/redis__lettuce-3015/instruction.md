Add hasNoSlots() Method to RedisClusterNode
## Feature Request

<!-- First of all: Have you checked the docs https://github.com/lettuce-io/lettuce-core/wiki, GitHub issues, or Stack Overflow whether someone else has already reported your issue? Maybe the feature already exists?-->

#### Is your feature request related to a problem? Please describe

In bug report [#2769](https://github.com/lettuce-io/lettuce-core/issues/2769), an issue was identified when handling Redis Cluster topology refreshes during node reconfigurations where nodes temporarily had no assigned slots. The maintainer suggested subclassing RedisClusterClient and overriding determinePartitions to address the issue. I followed the suggestion and initially used redisClusterNode.getSlots().isEmpty() to identify this case. However, I found that getSlots() is quite time-consuming, increasing the overhead of topology refreshes.

#### Describe the solution you'd like

To improve efficiency, I propose adding a method `hasNoSlots()` to`RedisClusterNode.` This method has much better performance than `getSlots().isEmpty()`
##### Proposed Method:
```
/**
     * Checks if the node has no slots assigned.
     *
     * @return {@code true} if the slots field is null or empty, {@code false} otherwise.
     */
    [HIDDEN]

```

#### Describe alternatives you've considered

Currently, the alternative is to use getSlots().isEmpty() to determine if a node has no slots assigned. However, this approach is inefficient because it involves generating a new list object, which adds overhead during topology refreshes.

#### Teachability, Documentation, Adoption, Migration Strategy

This feature request aims to improve the efficiency and readability of RedisClusterNode's API, particularly in scenarios involving cluster scaling and topology adjustments. I appreciate your consideration and am happy to make any additional changes or provide further details if needed.

### Additional contract requirements

- `hasNoSlots()` returns `true` when the node's slots are `null` or empty, and `false` when slots are assigned.
- `hasNoSlots()` must not allocate a new list object and must be substantially cheaper than `getSlots().isEmpty()`: evaluating it must not build the slot list that `getSlots()` creates.
