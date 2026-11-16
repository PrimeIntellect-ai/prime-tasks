Handle errors on worker's launch
Sourced from Elixir forum: [link](https://elixirforum.com/t/poolex-a-library-for-managing-pools-of-workers/54800/12?u=general-cbic)

> Poolex is not handling worker start errors and whole pool will die with MatchError if some extra worker fails to start. It makes this pool inapplicable for usage in environments where workers connect to external services (like databases or HTTP services which are most pooling use-cases) which can be unavailable or return 422 for example.
