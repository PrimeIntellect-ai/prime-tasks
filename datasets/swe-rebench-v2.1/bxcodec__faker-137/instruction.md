support custom random sources
A nice addition would be to be able to set custom random sources.

I see several reasons for that:
1. Seed a random source to generate a stable set of fake data
2. Use an alternate random generator, such as xorshift, for faster fake data generation
3. Have full control over when concurrency-safety is desirable or when it is not

### Additional contract requirements

Provide the public `SetRandomSource` API accepting a `math/rand.Source`. Subsequent pseudo-random fake-data generation must use the supplied source. The source is used as supplied, without automatically making it concurrency-safe; callers who want serialized access can wrap it with the public `NewSafeSource` before supplying it. This allows callers to choose whether their custom random-source access is concurrency-safe.
