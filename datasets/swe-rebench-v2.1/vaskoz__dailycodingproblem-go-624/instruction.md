Day 276
Good morning! Here's your coding interview problem for today.

This problem was asked by Dropbox.

Implement an efficient string matching algorithm.

That is, given a string of length N and a pattern of length k, write a program that searches for the pattern in the string with less than O(N * k) worst-case time complexity.

If the pattern is found, return the start index of its location. If not, return False.

### Additional contract requirements

Callers can invoke the matcher as `StringMatchKMP(input, substr string) int`. It returns the zero-based start index of the first occurrence when the pattern is present. When the pattern is absent, the result must be outside the range of valid starting indices; no particular sentinel value is required. The search must have worst-case time complexity asymptotically below O(N*k), where N is the input length and k is the pattern length.
