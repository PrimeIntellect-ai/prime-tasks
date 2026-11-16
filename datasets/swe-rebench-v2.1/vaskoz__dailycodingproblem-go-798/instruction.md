Day 397
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

You are given a list of jobs to be done, where each job is represented by a start time and end time. Two jobs are compatible if they don't overlap. Find the largest subset of compatible jobs.

For example, given the following jobs (there is no guarantee that jobs will be sorted):
```
[(0, 6),
(1, 4),
(3, 5),
(3, 8),
(4, 7),
(5, 9),
(6, 10),
(8, 11)]
```
Return:
```
[(1, 4),
(4, 7),
(8, 11)]
```

### Additional contract requirements

- Provide an exported Go `Job` type with `Start int` and `End int` fields.
- Provide the exported function `LargestSubsetCompatibleJobs(jobs []Job) []Job`, which returns a maximum-size compatible subset.
