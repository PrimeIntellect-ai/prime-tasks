ToHllSketch functions do not copy from other HllSketch
**Describe the bug**
`ToHllSketch` and `IterableToHllSketch` can both be intitialised with another HllSketch. It should be copied but is not.
Additionally, these fields should be JsonIgnored as they won't be used over the rest api and wouldn't work anyway.
