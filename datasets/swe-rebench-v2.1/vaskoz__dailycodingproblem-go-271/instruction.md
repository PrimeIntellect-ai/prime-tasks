Day 131
Good morning! Here's your coding interview problem for today.

This question was asked by Snapchat.

Given the head to a singly linked list, where each node also has a “random” pointer that points to anywhere in the linked list, deep clone the list.

### Additional contract requirements

In package `day131`, expose a `RandomSinglyLL` node type with exported fields `Value int`, `Next *RandomSinglyLL`, and `Random *RandomSinglyLL`. Expose `DeepCloneRandomSinglyLL(head *RandomSinglyLL) *RandomSinglyLL`; it returns `nil` for a nil head and otherwise returns a deep copy whose nodes are separate from the input, with the same values, `Next` ordering, and corresponding `Random` pointer relationships.
