Day 406
Good morning! Here's your coding interview problem for today.

This problem was asked by Quantcast.

You are presented with an array representing a Boolean expression. The elements are of two kinds:

`T` and `F`, representing the values `True` and `False`.
`&, |, and ^`, representing the bitwise operators for AND, OR, and XOR.
Determine the number of ways to group the array elements using parentheses so that the entire expression evaluates to True.

For example, suppose the input is `['F', '|', 'T', '&', 'T']`. In this case, there are two acceptable groupings: `(F | T) & T` and `F | (T & T)`.

### Additional contract requirements

- Provide a public function `CountParensEqualTrue(input []rune) int` in package `day406`.
- The input is a slice of runes of odd length in which even indices hold the literals `T` (true) or `F` (false) and odd indices hold the operators `&`, `|`, or `^`.
- The function returns the total number of distinct ways to insert parentheses into the expression so that it evaluates to true.
