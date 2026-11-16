Allow `:worker_module` to be the default `:pool_id`
Hello! Thanks for maintaining Poolex. I have a small ergonomics suggestion that I think would simplify things for the majority of use-cases: make `:pool_id` optional and use `:worker_module` as its default.

Assuming that most people have one pool per worker, this change would:

- Simplify the "getting started" story, as there's one less option that you need to know about for the basic case.
- Make run-site usage more clear; instead of `Poolex.run(:my_pool, ...)` and then having to look up the child spec to know for sure which worker is running, it's immediately visible as `Poolex.run(MyWorker, ...)`.

Alternative considered: Require manually setting the pool ID to be the worker module. This gets the call-site benefit above, but I believe the ergonomic and documentation benefit of letting the module be the default is worth it.

Thanks for considering!
