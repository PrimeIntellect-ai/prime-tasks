Day 76
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

You are given an N by M 2D matrix of lowercase letters. Determine the minimum number of columns that can be removed to ensure that each row is ordered from top to bottom lexicographically. That is, the letter at each column is lexicographically later as you go down each row. It does not matter whether each row itself is ordered lexicographically.

For example, given the following table:
```
cba
daf
ghi
```
This is not ordered because of the a in the center. We can remove the second column to make it ordered:
```
ca
df
gi
```
So your function should return 1, since we only needed to remove 1 column.

As another example, given the following table:

```abcdef```
Your function should return 0, since the rows are already ordered (there's only one row).

As another example, given the following table:
```
zyx
wvu
tsr
```
Your function should return 3, since we would need to remove all the columns to order it.

### Additional contract requirements

- Provide a public function `MinRemoveColumns(matrix [][]rune) int` in package `day76`.
- A column is ordered when its characters are non-decreasing from the top row to the bottom row; equal characters in the same column are allowed.
- An empty matrix is a valid input and requires no columns to be removed.
- The function runs in O(N*M) time for an N-row, M-column matrix.
