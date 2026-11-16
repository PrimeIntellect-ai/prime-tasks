Does not support NPM lockfile version 3
Lockfiles created using the NPM (9.x) that ships with the latest LTS of Node (18.x) use lockfile version 3. Unfortunately, this tool does not support these lockfiles. I suspect all the features do not work, but the options I have tested and confirmed do not work are `--validate-https` and `--validate-integrity`.

### Additional contract requirements

- npm lockfile version 3 package entries must be available to lockfile linting, including each package’s resolved URL and integrity value when present.
- The `--validate-https` option must validate resolved URLs from npm v3 lockfiles, and the `--validate-integrity` option must validate their integrity values.
