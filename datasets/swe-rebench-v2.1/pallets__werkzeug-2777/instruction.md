Elapsed and timestamp values are not available to filename_format function
When the `ProfilerMiddleware` `filename_format` argument is a callable, the callable will only receive the WSGI environ variable. However, the default format string can use the `elapsed` and `time` values. This means that one using a format function cannot recreate a similar output pattern. In my case, I'd like to use both, but format the timestamp differently.


Example: I'd like a filename of the form `2023-08-21:14:05:05.POST.myurl.13ms.prof`. I can get the timestamp by doing my own `datetime.now()` call, but the elapsed time is not available.

This problem is solvable by subclassing `ProfilerMiddleware` or writing ones own profiling middleware, but this seems like a useful thing to have in the core library so library users don't need to duplicate the `__call__()` code in their own projects.

I can submit a PR if this change is welcome.

### Additional contract requirements

When `filename_format` is a callable, it receives the WSGI environ with a `werkzeug.profiler` mapping. The mapping provides `elapsed` (the request's elapsed time in milliseconds) and `time` (a POSIX timestamp for the request), so the callable can use both values to construct a custom filename.
