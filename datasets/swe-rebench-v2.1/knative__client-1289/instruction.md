kn service describe should show # of instances
Today `kn service describe` will show this in it's output:
```
Revisions:
  100%  @latest (echo-yyhmp-6) [6] (4d)
```
The `[6]` is interesting. I believe that the generation number - or in user's terms, my version # of my app. That's (sort of) interesting, but at first I thought it was the # of instances of this Revision that were running... that would be far more useful to me.

Proposal: show the # of instances of each revision instead of the generation #. I'm not really sure what the generation # tells the user, or what interesting thing they can do with it. It seems to me that seeing the revision name change in that list would be enough to indicate that there are multiple revisions out there.

This may be controversial because it means using a non-knative api (e.g. pods, or deployment) but I think we need to think about what's best (and most useful) for the user, and I think being able to see how their app is scaling (perhaps out of control!) would be very useful.

We could even make it conditional, and try to get the list number of instances and if it fails due to an known API then just not show it (and no error msg), but if the API is there then show the info.

### Additional contract requirements

- `kn service describe` must display, for each revision listed under `Revisions:`, an additional line `Replicas: <actual>/<desired>`, where `<actual>` is the revision's actual number of running instances and `<desired>` is the desired number of instances.
- `kn revision describe` must display the same `Replicas: <actual>/<desired>` line.
- The generation number shown in brackets (for example `[1]`) in the `kn service describe` revision header is retained.
