Handle `PROC_NULL` in a consistent way
Handle `MPI.Consts.MPI_PROC_NULL[]` in a similar fashion to `MPI_COMM_TYPE_SHARED` (related / by analogy to #584).

In short, avoid exposing the `MPI.Const.XYZ[]` to the user.

_Note: feel free to edit this issue as the terminology may not be most accurate._

### Additional contract requirements

- Provide `MPI.PROC_NULL` as a public value equivalent to the MPI null-process constant. Also provide `MPI.ANY_SOURCE`, `MPI.ANY_TAG`, and `MPI.SUCCESS` as public values corresponding to the MPI wildcard-source, wildcard-tag, and success constants, respectively, so callers need not access low-level MPI constants directly.
- Using `MPI.PROC_NULL` as a send destination sends no message. Using it as a receive source leaves the receive buffer unchanged.
