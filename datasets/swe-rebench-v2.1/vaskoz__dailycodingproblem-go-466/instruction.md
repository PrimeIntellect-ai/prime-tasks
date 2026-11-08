Day 225
Good morning! Here's your coding interview problem for today.

This problem was asked by Bloomberg.

There are N prisoners standing in a circle, waiting to be executed. The executions are carried out starting with the kth person, and removing every successive kth person going clockwise until there is no one left.

Given N and k, write an algorithm to determine where a prisoner should stand in order to be the last survivor.

For example, if N = 5 and k = 2, the order of executions would be [2, 4, 1, 5, 3], so you should return 3.

Bonus: Find an O(log N) solution if k = 2.

### Additional contract requirements

Expose the solution in the `day225` package as `JosephusGeneral(n, k int) int`. For valid positive inputs, return the 1-based position of the last survivor.
