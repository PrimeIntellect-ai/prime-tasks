$RESOLVED_VERSION not expanded when set via action input
Using the `name` input:
```yml
...
jobs:
  update_release_draft:
    runs-on: ubuntu-latest
    steps:
      - uses: release-drafter/release-drafter@v5
        with:
          name: "$RESOLVED_VERSION"
...
```
the release draft will be named `$RESOLVED_VERSION`, which obviously is not what I expected.

However inside the config file
```
name-template: '$RESOLVED_VERSION'
```
the release draft will correctly be named with the version, e.g. `1.0.0`.

Now, the `name` overrides the `name-template`:
<kbd><img width="800" src="https://user-images.githubusercontent.com/644927/151940732-1d15cfae-778f-4564-9a7d-fd506dc809b9.png" /></kbd>

I expect both configs behave identically, I would have guessed variable expansion takes places after the override happened, so it shouldn't matter where the config string came from.
