[Feature] Add new spot allocation strategies
AWS announced a new spot allocation strategy, "Price Capacity Optimized".

https://aws.amazon.com/blogs/compute/introducing-price-capacity-optimized-allocation-strategy-for-ec2-spot-instances/

This option is not available when setting nodegroup `spotAllocationStrategy`:

```yaml
#<snip>
  - name: nodegroup-name
    labels:
      lifecycle: Ec2Spot
      spotInstance: "true:PreferNoSchedule"
    #<snip>
    instancesDistribution:
      instanceTypes:
        - t3.medium
        - t2.medium
      spotAllocationStrategy: "price-capacity-optimized"
```

Results in:

```bash
Error: could not create cluster provider from options: spotAllocationStrategy
should be one of: lowest-price, capacity-optimized,
capacity-optimized-prioritized
```

Please add `"price-capacity-optimized"` as a valid `spotAllocationStrategy`.

### Additional contract requirements

- When `spotAllocationStrategy` is unsupported, validation must return the exact error `spotAllocationStrategy should be one of: [lowest-price diversified capacity-optimized capacity-optimized-prioritized price-capacity-optimized]`.
