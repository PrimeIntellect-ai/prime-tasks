Day 353
Good morning! Here's your coding interview problem for today.

This problem was asked by Square.

You are given a histogram consisting of rectangles of different heights. These heights are represented in an input list, such that `[1, 3, 2, 5]` corresponds to the following diagram:
```
      x
      x
  x   x
  x x x
x x x x
```
Determine the area of the largest rectangle that can be formed only from the bars of the histogram. For the diagram above, for example, this would be six, representing the `2 x 3` area at the bottom right.

### Additional contract requirements

In the Go package `day353`, expose `LargestRectangleHistogram(hist []int) int`. The input contains non-negative bar heights. Return the maximum area of a rectangle spanning contiguous bars.
