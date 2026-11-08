Day 122
Good morning! Here's your coding interview problem for today.

This question was asked by Zillow.

You are given a 2-d matrix where each cell represents number of coins in that cell. Assuming we start at `matrix[0][0]`, and ***can only move right or down***, find the maximum number of coins you can collect by the bottom right corner.

For example, in this matrix
```
0 3 1 1
2 0 0 4
1 5 3 1
```
The most we can collect is `0 + 2 + 1 + 5 + 3 + 1 = 12 coins.`

### Additional contract requirements

- Provide the public function `MaxCoinsPath(grid [][]int) int` to return the maximum number of coins collectable under the movement rules above.
