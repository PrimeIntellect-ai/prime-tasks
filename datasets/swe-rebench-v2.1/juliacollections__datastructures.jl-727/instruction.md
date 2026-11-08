append! broken for MutableLinkedLists?
Hi! I been having a few problems with the MutableLinkedList type, (infinite loops and segfaults).
I've tested up to version 18.9 and reduced the problems to this minimal example:

```
julia> using DataStructures
julia> l1 = MutableLinkedList{Int}(1:5...);
julia> l2 = MutableLinkedList{Int}(10:15...);
julia> append!(l1,l2);
julia> collect(l1)
ERROR:
signal (11): Segmentation fault
in expression starting at none:0
```
