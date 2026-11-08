stats: add UnregisterView and then remove *View.Unregister for parity of APIs
I was just reviewing https://github.com/census-instrumentation/opencensus-go/pull/249/files and noticed that the stats API has
stats.RegisterView
but no matching call to stats.UnregisterView

and that instead the caller has to do *View.Unregister(), of which there also isn't a match method *View.Register()

Notice that RegisterView and *View.UnregisterView look like the perfect match
https://github.com/census-instrumentation/opencensus-go/blob/86bea64327bd7d353334ff858a2e6675a3122b7b/stats/worker.go#L115-L122
and
https://github.com/census-instrumentation/opencensus-go/blob/86bea64327bd7d353334ff858a2e6675a3122b7b/stats/worker.go#L127-L134

I'd say let's deprecate/remove *View.Unregister and instead add the UnregisterView helper since
we already have *View.Subscribe and *View.Unsubscribe of which Subscribe and Unsubscribe logically use RegisterView and UnregisterView respectively.

### Additional contract requirements

- The former `(*View).Unregister` method must be removed from the public API, not merely deprecated. `UnregisterView` replaces it, so `*View` must no longer expose an `Unregister` method.
