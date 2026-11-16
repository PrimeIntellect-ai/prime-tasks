Add constructor runtime to fxevent.Run events
**Is your feature request related to a problem? Please describe.**
Recently I had to investigate a service not starting up properly due to dependency construction taking a long time in certain zone. While we log fxevent.Run events when a constructor runs and returns results and/or error, it lacks the information on how long a certain constructor took to run, which barred us from being able to further investigate and find out which part of the DI graph could be slowing down and come up with some hypotheses on what could be going on in that zone.

**Describe the solution you'd like**
I propose that we include the runtime of each constructor in fxevent.Run events.

**Describe alternatives you've considered**
Collecting cpu profiles at application start-up, including provides, runs, invokes, and OnStart hooks, would also have enabled us to identify which constructors are running slower than others. However, in this particular situation, the docker container that's starting the service up was being terminated in the middle of DI graph construction, so optionally emitting CPU profiles at start-up wouldn't have helped us.

**Is this a breaking change?**
This is just adding more information to an fxevent. I don't think this is a breaking change.

### Additional contract requirements

Each `fxevent.Run` event exposes the elapsed execution duration through a public `Runtime` field of type `time.Duration`.
