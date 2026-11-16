Surface any intermediate arrays from rechunk in DAG
Currently the rechunk operation is treated as a black box, and any intermediate arrays that it creates are not shown in the DAG.

(Intermediate arrays are also named differently - they take the form [`array-nnn-intermediate`](https://github.com/tomwhite/cubed/blob/main/cubed/core/ops.py#L599). Note that the number of tasks is [adjusted appropriately](https://github.com/tomwhite/cubed/blob/0110a40430804a45c1bda75d1934e8aff71c4ca1/cubed/primitive/rechunk.py#L60-L61).)

I propose making intermediate arrays top-level arrays in the DAG. This would make progress bars clearer (currently they are split into two rounds of computations if there is an intermediate array), and more importantly would offer more opportunities for fusing rechunk and blockwise operations in some cases (e.g. #221). The downside would be that DAGs might be more cluttered - but with better optimizations the number of nodes in the DAG will come down even more, so it should be a net improvement.
