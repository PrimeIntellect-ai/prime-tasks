Phrasing of error messages for runtime stack overflow
Error messages for runtime stack overflow or excessive time consumption should never include a phrasing like "infinite loop detected" or the like. Infinite loops cannot be detected.

(This may have been fixed already; cannot check this right now.)

### Additional contract requirements

- For runtime stack overflow, the error message must use the exact wording `Maximum call stack size exceeded`.
