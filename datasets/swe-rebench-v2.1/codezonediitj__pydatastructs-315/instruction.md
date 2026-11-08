Longest common subsequence
Description of the problem
LCS Problem Statement: Given two sequences, find the length of longest subsequence present in both of them. A subsequence is a sequence that appears in the same relative order, but not necessarily contiguous.
Example of the problem
For example, “abc”, “abg”, “bdf”, “aeg”, ‘”acefg”, .. etc are subsequences of “abcdefg”.

### Additional contract requirements

- The public callable name is `longest_common_subsequence`.
- The function returns the longest common subsequence itself — the sequence of common elements in their original relative order — not merely its length. The string form of the returned value is the list of those elements, for example `['A', 'S', 'C', 'I', 'I']`.
- If the two sequences share no elements, the function returns an empty result whose string form is `[]`.
