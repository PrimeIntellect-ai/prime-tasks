Provide new idle workers to waiting callers after extending pool size
Sourced from Elixir Forum: [link](https://elixirforum.com/t/poolex-a-library-for-managing-pools-of-workers/54800/22?u=general-cbic)

> Consider this situation: we have a pool, all workers are busy and there is a queue of waiting callers. Then pool receives a call to create more idle workers, but these workers won’t be returned to waiting callers.
