lmdbsync: default MapResizeHandler strategy should have exponential backoff
Right now there is a constant delay. This is doesn't seem terrible for the default (low) number of retries. But increasing the number of retries is not as effective as it should be.

Also, it seems a little weird that the delay function only gets called after one immediate attempt. It seems more flexible and consistent to always call the delay function.
