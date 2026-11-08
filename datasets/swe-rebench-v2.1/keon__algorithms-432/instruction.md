Test fail. arrays/plus_one makes tests fail
The function plus_one_v3() tries to access the index as if it was an actual index (number) but [HIDDEN] for all the items in the list

I discovered this while making a PR for another issue since it would reject my build.

Already making a PR changing it so the tests run again.

### Additional contract requirements

`plus_one_v3(num_arr)` must return the digit list for the input number incremented by one, using the same big-endian digit representation as `plus_one_v1` and `plus_one_v2`. For example: `plus_one_v3([0]) == [1]`, `plus_one_v3([9]) == [1, 0]`, `plus_one_v3([1, 0, 9]) == [1, 1, 0]`, and `plus_one_v3([9, 9, 9, 9]) == [1, 0, 0, 0, 0]`.
