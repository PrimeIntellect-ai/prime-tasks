Day 191
Good morning! Here's your coding interview problem for today.

This problem was asked by Stripe.

Given a collection of intervals, find the minimum number of intervals you need to remove to make the rest of the intervals non-overlapping.

Intervals can "touch", such as `[0, 1]` and `[1, 2]`, but they won't be considered overlapping.

For example, given the intervals `(7, 9), (2, 4), (5, 8)`, return `1` as the last interval can be removed and the first two won't overlap.

The intervals are not necessarily sorted in any order.

### Additional contract requirements

Expose the behavior through the Go function `MinRemoveNoOverlap(intervals []Interval) int`. Callers must be able to construct `Interval` values with integer `Start` and `End` fields.
