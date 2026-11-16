KthSelector does not consider natural order of doubles
As a user I would expect that sorting the array and taking the k-th element yields the same result as using the KthSelector. Unfortunately, this is not true if the array contains NaN or -0/+0 values, [HIDDEN]

### Additional contract requirements

- For a double array, KthSelector must return the value at index k under natural double ordering, matching the result of sorting the array, including when the array contains NaN or signed zeros.
