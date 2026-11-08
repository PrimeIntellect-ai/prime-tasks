Day 210
Good morning! Here's your coding interview problem for today.

This problem was asked by Apple.

A Collatz sequence in mathematics can be defined as follows. Starting with any positive integer:

if n is even, the next number in the sequence is n / 2
if n is odd, the next number in the sequence is 3n + 1
It is conjectured that every such sequence eventually reaches the number 1. Test this conjecture.

Bonus: What input n <= 1000000 gives the longest sequence?

### Additional contract requirements

For the conjecture check, evaluate positive starting values from 1 through 1,000,000 using the stated even/odd transitions and determine whether each sequence reaches 1. For the bonus, identify the starting value at most 1,000,000 with the longest sequence. In the Go package `day210`, expose this search as `LongestCollatzSequence(max int) (int, int)`, where `max` is an inclusive upper bound; return the starting value with the longest sequence among values from 1 through `max`, followed by its number of transitions to 1.
