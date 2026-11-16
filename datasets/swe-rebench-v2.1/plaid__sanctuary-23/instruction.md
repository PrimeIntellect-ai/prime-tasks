S.pluck?
This is really sheer laziness on my part but my code is littered with `R.map(S.get('key'), arr))`, it's an improvement on having to remember to do `R.reject(R.isNil, R.pluck('key', arr))` whenever I use `R.pluck` but it would be nice to have some sugar around such a common pattern.
