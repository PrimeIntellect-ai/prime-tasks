Day 104
Good morning! Here's your coding interview problem for today.

This problem was asked by Google.

Determine whether a doubly linked list is a palindrome. What if it’s singly linked?

For example, `1 -> 4 -> 3 -> 4 -> 1` returns `true` while `1 -> 4` returns `false`.

### Additional contract requirements

In Go package `day104`, provide the exported node types `DoublyLL` and `SinglyLL`. Each node has an integer `Value` and a `Next` pointer to a node of the same type; `DoublyLL` also has a `Prev` pointer. Provide `IsPalindromeDoublyLL(head *DoublyLL) bool` for doubly linked lists and `IsPalindromeSinglyLLStack(head *SinglyLL) bool` for singly linked lists. Each function returns whether the list's sequence of values reads the same forward and backward.
