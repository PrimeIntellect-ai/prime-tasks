Question: Handle partial ticks on TimeSeries
Hi!

Is there a way to handle partial ticks on TimeSeries? Such as keep changing over and over the one at the end index, and switch to the next one just when it is the final for the timeframe.

I know that there are other possible ways to do it, but for example, I want to run indicators (e.g. stop-loss) before receiving the final tick for the 30 min.
One way that I think is to create a new TimeSeries every time, but I'm sure this wouldn't have a good performance and probably can't leverage the cached indicators.


Also, if you are okay with it and don't see any problems, I can submit a PR adding a new `addTick` method with a `partial` flag.


Thank you!
