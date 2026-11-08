Hooks pre-fetching
Hi,

I want to suggest introducing a command for downloading all required hooks forcefully. The use case is simple:
1. I pack everything needed for testing into container
2. I deploy that into CI
3. It gets built and tests are ran

I'd like to separate fetching of the hooks and pre-installing them into a build step. This would allow me use caching for containers, saving time for tests.

P.S. Perhaps it's needed to add some argument to `run` command, so that it won't try downloading stuff when executing tests.

### Additional contract requirements

- The standalone pre-installation operation must make hooks from every repository in the configuration available, not only the first repository.
