7.9.0: Can't make batch requests without `provider._is_batching`
### What happened?

in < 7.9.0 you could make both batch and single requests without any fuckery around `_is_batching`

### Code that produced the error

```python
def _raise_stray_errors_from_cache(self) -> None:
        """
        Check the request response cache for any errors not tied to current requests
        and raise them if found.
        """
        [HIDDEN]
            for (
                response
            ) in [HIDDEN]:
                [HIDDEN]
                if "error" in response and request is None:
                    # if we find an error response in the cache without a corresponding
                    # request, raise the error
                    validate_rpc_response_and_raise_if_error(
                        response, None, logger=self.logger
                    )
```

### Full error output

```shell
In: web3\providers\persistent\persistent.py
generate_cache_key(response["id"])
                       ~~~~~~~~^^^^^^
TypeError: list indices must be integers or slices, not str
```

### Fill this section in if you know how this could or should be fixed

revert whatever this is

### web3 Version

_No response_

### Python Version

_No response_

### Operating System

_No response_

### Output from `pip freeze`

```shell

```

### Additional contract requirements

- A provider's batch-request operation must work when `_is_batching` is initially false, without requiring the caller to set that flag, and must leave the provider ready for ordinary single-request use afterward.
- A list-valued response-cache entry must not cause the reported `TypeError` during stray-error checking.
