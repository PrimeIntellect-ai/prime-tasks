Day 194
Good morning! Here's your coding interview problem for today.

This problem was asked by Facebook.

Suppose you are given two lists of n points, one list `p1, p2, ..., pn` on the line y = 0 and the other list `q1, q2, ..., qn` on the line y = 1. Imagine a set of n line segments connecting each point pi to qi. Write an algorithm to determine how many pairs of the line segments intersect.

### Additional contract requirements

- Provide the solution in package `day194` as `func CountIntersectionsBrute(p, q []int) int`. The slices contain the x-coordinates of corresponding points on `y = 0` and `y = 1`, and must have the same length.
- Return the number of unordered pairs of segments whose endpoints have strictly opposite left-to-right order on the two lines. Pairs that only touch at an endpoint, share an endpoint, or are coincident do not count.
