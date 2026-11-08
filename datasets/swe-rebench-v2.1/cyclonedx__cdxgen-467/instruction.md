[Gradle] cdxgen doesn't support 'jetify'
For an upcoming audit, I was working through all components with unknown licenses and I found this error. Had to read up on Gradle and the dependency tree to figure out what was going on and why cdxgen is (probably) making this mistake.

Our project has a dependency on `com.android.support:appcompat-v7:26.1.0`, which is being replaced by having a setting `android.enableJetifier=true` in our gradle.properties. This means that when rendering the dependency tree, Gradle outputs this:
`|    +--- com.android.support:appcompat-v7:26.1.0 -> androidx.appcompat:appcompat:1.2.0 (*)`

From what I've seen in the code the last couple of days, cdxgen only expects a version after the '->', so it adds a dependency `com.android.support:appcompat-v7:androidx.appcompat', which simply doesn't exist.

I think I know how and where to fix it, so unless somebody wants to fix it right away, I'll give it a go tonight/tomorrow.
