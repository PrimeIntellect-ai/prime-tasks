Read git-cliff config file
## Motivations

We use [git-cliff](https://github.com/orhun/git-cliff) to generate the changelog. However, we use a fixed configuration.
It would be nice to allow users to specify their own git-cliff config file.

### Additional contract requirements

- The `release-plz update` command must let users select a git-cliff configuration file with
  `--changelog-config <PATH>`.
- When a custom git-cliff configuration file is selected, generated changelog formatting must
  follow that file's format (for example its changelog header/body and commit grouping) instead
  of the built-in default format.
