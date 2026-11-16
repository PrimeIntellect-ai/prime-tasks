Prohibit invoking 'io.github.serpro69.kfaker.fakerConfig' inside 'faker' DSL
Would be nice to prohibit invoking `fakerConfig` inside the `faker` function to make the api more clearer.
Not sure if it's possible though.

```
fun main() {
    val faker1 = faker {
        fakerConfig {
            randomSeed = 42
            locale = "uk"
        }
    }

    val config = fakerConfig {
        randomSeed = 42
        locale = "uk"
    }
    val faker2 = Faker(config)

    println(faker1.separator.separator()) // &
    println(faker2.separator.separator()) // та
}
```

### Additional contract requirements

- Inside the `faker { … }` DSL, an unqualified call to `fakerConfig { … }` must apply the supplied configuration to the `Faker` being built. The resulting `Faker` must reflect the configured `locale`, `random`, and `randomSeed`; the call must not silently construct and discard a `FakerConfig`.
- A package-qualified call to the top-level `io.github.serpro69.kfaker.fakerConfig { … }` inside the DSL does not configure the `Faker` being built; use the unqualified DSL call to configure it.
