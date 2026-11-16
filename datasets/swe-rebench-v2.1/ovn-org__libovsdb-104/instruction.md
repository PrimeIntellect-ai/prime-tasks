List() does not work on empty Lists
Currently List() respects the capacity of the given list and does not resize it. This is intended so that a client that preallocates a list for optimization purposes is not returned an increased slice.
However, the side efect is that a zero capacity (`[]MyRouter{}`) slice does not get populated.
We should consider a slice with capacity==0 in the same way as an nil slice
