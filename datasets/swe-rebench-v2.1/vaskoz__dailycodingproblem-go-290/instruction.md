Day 138
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Find the minimum number of coins required to make n cents.

You can use standard American denominations, that is, 1¢, 5¢, 10¢, and 25¢.

For example, given n = 16, return 3 since we can make it with a 10¢, a 5¢, and a 1¢.

### Additional contract requirements

- The package is `day138`.
- Add a public function `ErrNotPossible() error` that returns a sentinel error value indicating that the requested amount cannot be made with the supplied denominations. The same error value is returned on each call.
- Add a public function `MinCurrencyRequiredBrute(amt int, denomCents []int) (int, error)` that returns the minimum number of coins required to make `amt` cents using the denominations supplied in `denomCents`. The error is nil on success, or `ErrNotPossible()` when the amount cannot be formed with those denominations.
- Add a public function `MinCurrencyRequiredSmarter(amt int, denomCents []int) (int, error)` that returns the minimum number of coins required to make `amt` cents using the denominations supplied in `denomCents`. The error is nil on success, or `ErrNotPossible()` when the amount cannot be formed with those denominations.
- The amount `amt` is a non-negative integer. An amount of zero requires zero coins and succeeds with a nil error.
