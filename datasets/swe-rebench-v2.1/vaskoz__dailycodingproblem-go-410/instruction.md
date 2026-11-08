Day 199
Good morning! Here's your coding interview problem for today.

This problem was asked by Facebook.

Given a string of parentheses, find the balanced string that can be produced from it using the minimum number of insertions and deletions. If there are multiple solutions, return any of them.

For example, given `"(()"`, you could return `"(())"`. Given `"))()("`, you could return `"()()()()"`.

### Additional contract requirements

Expose this operation as the Go function `BalanceParens(parens string) string`. When more than one balanced result uses the minimum number of insertions and deletions, any such result is acceptable.
