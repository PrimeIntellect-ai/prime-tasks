Throwaway MEASURE instructions are not properly dealt with in classical register autodetection
Running a Quil simple program containing MEASURE instruction that does not store its result, such as

```
X 0
MEASURE 0
```
results into an error due to the fact that `get_classical_addresses_from_program` is not equipped to handle this case:

```
AttributeError: 'NoneType' object has no attribute 'address'
```
