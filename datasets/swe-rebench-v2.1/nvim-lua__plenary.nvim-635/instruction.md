job on_stdout is not retrieving all data
Hi and thanks for this awesome project!

I have been using the `plenary.curl` module recently, especially it's capability to stream http responses using the underlying `plenary.job` `on_stdout` mechanism.

While using it, I discovered a few weired edge-cases where the last chunks of streamed data is only available via `job:result()`, but not the `on_stdout` callback.

Looking at the tests I found [two related test cases that are marked as `pending`](https://github.com/nvim-lua/plenary.nvim/blob/master/tests/plenary/job_spec.lua#L102), so it seems like this has been a known issue.

As this is unnecessarily complicating my usage of the `plenary.curl` streaming functionality, as I would have to use both `on_stdout` and then at the end compare what has not yet been processed from the `job:result()`, I would like to resolve this bug.

Please let me know if I have misunderstood anything or you have further thoughts.
I will open a PR with a potential solution.

Thanks a lot!
