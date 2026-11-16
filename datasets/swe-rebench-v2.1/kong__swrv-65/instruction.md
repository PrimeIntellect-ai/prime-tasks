revalidations firing when key is falsy
revalidations are firing even if the key value returns falsy

### Additional contract requirements

- Do not initiate revalidation when the resolved key is falsy, including after a previously truthy key becomes falsy and when focus triggers revalidation.
