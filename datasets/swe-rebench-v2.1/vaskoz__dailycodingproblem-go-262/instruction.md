Day 127
Good morning! Here's your coding interview problem for today.

This problem was asked by Microsoft.

Let's represent an integer in a linked list format by having each node represent a digit in the number. The nodes make up the number in reversed order.

For example, the following linked list:

1 -> 2 -> 3 -> 4 -> 5
is the number 54321.

Given two linked lists in this format, return their sum in the same linked list format.

For example, given

9 -> 9
5 -> 2
return 124 (99 + 25) as:

4 -> 2 -> 1

### Additional contract requirements

Expose the operation in Go as `SumRevLLNum(first, second *RevLLNum) *RevLLNum`. `RevLLNum` is a struct with fields in this order: `Digit int` and `Next *RevLLNum`; the first node represents the least significant digit. The operation returns the sum as a linked list in that same reversed-digit order.
