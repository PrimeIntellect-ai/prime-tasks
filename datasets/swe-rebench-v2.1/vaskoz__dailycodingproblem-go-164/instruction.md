Day 77
Good morning! Here's your coding interview problem for today.

This problem was asked by Snapchat.

Given a list of possibly overlapping intervals, return a new list of intervals where all overlapping intervals have been merged.

The input list is not necessarily ordered in any way.

For example, given `[(1, 3), (5, 8), (4, 10), (20, 25)]`, you should return `[(1, 3), (4, 10), (20, 25)]`.

### Additional contract requirements

- The solution is provided in package `day77`. It defines a public struct `Interval` with exported integer fields `Start` and `End`, and a public function `MergeOverlappingIntervals(intervals []Interval) []Interval`.
- The returned slice contains the merged intervals ordered by ascending `Start`.
- When the input slice is nil or empty, the function returns `nil`.
- Intervals that meet only at a single endpoint (for example `(1, 3)` and `(3, 5)`) are not considered overlapping and are returned as separate intervals.
