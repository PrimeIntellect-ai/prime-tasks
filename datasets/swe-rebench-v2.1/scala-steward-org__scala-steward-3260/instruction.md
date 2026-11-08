Version.Component.parse parses githash as separate components
Hi, I hit an interesting case recently which I believe boils down a possible issue in Version.Component.parse (hence the title).

Say I have the following versions:

```scala
val currentVersion = Version("1.0.0+1319.ae77058")
val nextVersion = Version("1.0.0+1320.38b57aa")
```

The version suffix consists of a monotonically increasing build number and a githash.

I would expect `currentVersion.selectNext(List(nextVersion)` to return `Some(nextVersion)`.

However, it actually returns `None`.

When I looked into this more, it turns out that this is returning `None` because of how nextVersion is parsed:

```scala
Version.Component.parse("1.0.0+1320.38b57aa").foreach(println(_))
```

returns:

```
Numeric(1)
Separator(.)
Numeric(0)
Separator(.)
Numeric(0)
Separator(+)
Numeric(1320)
Separator(.)
[HIDDEN]
```

[HIDDEN]

This turns out to be the case for any first containing substrings `m`, `ea`, `rc`, etc.

For example, this ends up printing None:

```scala
import org.scalasteward.core.data.Version

val currentVersion = Version("1.0.0+1319.ae77058")
val nextVersions = List(
  Version("1.0.0+1320.38b57aa"),
  Version("1.0.0+1320.38m57aa"),
  Version("1.0.0+1320.38ea57aa")
)

println(currentVersion.selectNext(nextVersions)) // None
```

Some thoughts/observations:

I would have expected "38m57aa" to get parsed as a component, not a set of components.

It seems like scala-steward already knows that the dot character is a separator, it just doesn't know that "38m57aa" is a githash.

The component parser does have [HIDDEN], but it's unclear whether this particular substring matches that pattern. I'm not familiar with the cats parser syntax, so I can't really interpret whether this is desired or a defect.

Even if this particular case was parsed "correctly" (by my interpretation), what happens when the githash component starts with a b or m or ea?

### Additional contract requirements

- For the stated current and next versions, `currentVersion.selectNext(List(nextVersion))` should return `Some(nextVersion)`.
- When a version suffix contains a monotonically increasing build number followed by a dot-delimited hexadecimal githash, the hash must not be treated as prerelease text in a way that causes an otherwise eligible higher-build version to be omitted from `selectNext`.
