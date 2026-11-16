ContextTracer.finish() does not end remaining spans
From reading the documentation of Tracer.finish() it looks like calling finish() on a tracer object should end all remaining spans and send them to exporters. However, it looks like the current implementation
just [resets the internal span list](https://github.com/census-instrumentation/opencensus-python/blob/master/opencensus/trace/tracers/context_tracer.py#L54). This usually isn't a problem unless you get into a state where all spans are not ended properly.

[HIDDEN]

Happy to submit a PR for this change if everyone agrees on the proposal.

### Additional contract requirements

After `finish()` completes, its remaining-span tracking contains no spans that were pending when it was called.
