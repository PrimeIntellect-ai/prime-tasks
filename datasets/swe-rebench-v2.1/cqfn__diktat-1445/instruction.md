USE_DATA_CLASS rule is not triggered on classes without a body
The following **main** scenario for `USE_DATA_CLASS` is not processed properly:

```
class ExecutionUpdateDto(
    val id: Long,
    val status: ExecutionStatus,
)
```
