sample rate not being passed with events
At the moment, we aren't sending a sampleRate in any events, even if the deterministic sampler is in use.

Should check how the go beeline is handling this and duplicate behavior.
