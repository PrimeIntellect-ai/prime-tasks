ENH Better error message for `get_result` return format
Hello,

I ran into the following error
```
TypeError: benchopt_benchmarks.bench.objective.Objective.evaluate_result() argument after ** must be a mapping, not numpy.ndarray
```
because I was using an older benchmark as a template that returned a unique numpy array.

The fix was to return a dictionary which is easy but the error message was  abit cryptic IMHO (not everyone has access to @tomMoral !).

I suggest to change the error message to something that explicitly say a dictionary is required.

### Additional contract requirements

- The TypeError message must contain the exact text `get_result` should be a dict `.
