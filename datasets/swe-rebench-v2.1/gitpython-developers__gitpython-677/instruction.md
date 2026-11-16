Environment values passed to Repo.clone_from() are not kept in the resulting repo
    r = Repo.clone_from("git@github.com:bpiotr/whatever_repo.git", "/tmp/repo", env={"key": "value"})
    r.git.environment()
    {}

This is not what I expected when I called `Repo.clone_from` and documentation does not elaborate on the transient nature of the `env` here so IMHO this is a bug.

BTW it costed me quite a while to figure out that `clone_from` actually uses `env` but any subsequent operations on the result needs it to have it set again.

### Additional contract requirements

Environment values supplied to `Repo.clone_from()` remain available on the returned repository's Git wrapper and are applied to subsequent Git operations through that repository.
