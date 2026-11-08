Day 293
Good morning! Here's your coding interview problem for today.

This problem was asked by Uber.

You have N stones in a row, and would like to create from them a pyramid. This pyramid should be constructed such that the height of each stone increases by one until reaching the tallest stone, after which the heights decrease by one. In addition, the start and end stones of the pyramid should each be one stone high.

You can change the height of any stone by paying a cost of `1` unit to lower its height by `1`, as many times as necessary. Given this information, determine the lowest cost method to produce this pyramid.

For example, given the stones `[1, 1, 3, 3, 2, 1]`, the optimal solution is to pay `2` to create `[0, 1, 2, 3, 2, 1]`.

### Additional contract requirements

The pyramid occupies a contiguous segment of the row. Stones before and after that segment have target height zero, so zero-height positions outside the pyramid are allowed. The target height at every position must be no greater than the original height. Return a target arrangement with the lowest total reduction cost; if several arrangements have the same lowest cost, any of them is acceptable.

In package `day293`, provide `LowestCostPyramid(stones []int) ([]int, int)`. The returned slice contains the target heights, and the returned integer is the total cost of the reductions.
