list_inference_endpoints fails with Date parsing error
### Describe the bug

Pretty simple, the `list_inference_endpoints` is completely broken. It fails with some parse date error, see stacktrace.

### Reproduction

list_inference_endpoints(namespace=NAMESPACE, token=HF_API_KEY)

### Logs

```shell
File "/Users/jd/code/prompt-js/prompt-worker-py/activities/llama_guard.py", line 98, in check_endpoint
    x = list_inference_endpoints(namespace=NAMESPACE, token=HF_API_KEY)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/hf_api.py", line 7716, in list_inference_endpoints
    return [
           ^
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/hf_api.py", line 7717, in <listcomp>
    InferenceEndpoint.from_raw(endpoint, namespace=namespace, token=token)
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/_inference_endpoints.py", line 134, in from_raw
    return cls(raw=raw, namespace=namespace, _token=token, _api=api)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "<string>", line 7, in __init__
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/_inference_endpoints.py", line 138, in __post_init__
    self._populate_from_raw()
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/_inference_endpoints.py", line 394, in _populate_from_raw
    [HIDDEN]
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/jd/code/prompt-js/prompt-worker-py/.venv/lib/python3.11/site-packages/huggingface_hub/utils/_datetime.py", line 59, in parse_datetime
    raise ValueError(
ValueError: Cannot parse '2024-11-20T20:01:58Z' as a datetime. Date string is expected to follow '%Y-%m-%dT%H:%M:%S.%fZ' pattern.
```


### System info

```shell
- huggingface_hub version: 0.26.2
- Platform: macOS-14.4.1-arm64-arm-64bit
- Python version: 3.11.7
- Running in iPython ?: No
- Running in notebook ?: No
- Running in Google Colab ?: No
- Running in Google Colab Enterprise ?: No
- Token path ?: /Users/jd/.cache/huggingface/token
- Has saved token ?: True
- Who am I ?: jamie-de
- Configured git credential helpers: osxkeychain
- FastAI: N/A
- Tensorflow: N/A
- Torch: 2.2.0
- Jinja2: 3.1.4
- Graphviz: N/A
- keras: N/A
- Pydot: N/A
- Pillow: 11.0.0
- hf_transfer: N/A
- gradio: N/A
- tensorboard: N/A
- numpy: 1.25.1
- pydantic: 2.9.2
- aiohttp: 3.10.11
- ENDPOINT: https://huggingface.co
- HF_HUB_CACHE: /Users/jd/.cache/huggingface/hub
- HF_ASSETS_CACHE: /Users/jd/.cache/huggingface/assets
- HF_TOKEN_PATH: /Users/jd/.cache/huggingface/token
- HF_STORED_TOKENS_PATH: /Users/jd/.cache/huggingface/stored_tokens
- HF_HUB_OFFLINE: False
- HF_HUB_DISABLE_TELEMETRY: False
- HF_HUB_DISABLE_PROGRESS_BARS: None
- HF_HUB_DISABLE_SYMLINKS_WARNING: False
- HF_HUB_DISABLE_EXPERIMENTAL_WARNING: False
- HF_HUB_DISABLE_IMPLICIT_TOKEN: False
- HF_HUB_ENABLE_HF_TRANSFER: False
- HF_HUB_ETAG_TIMEOUT: 10
- HF_HUB_DOWNLOAD_TIMEOUT: 10
```

### Additional contract requirements

- `parse_datetime` must accept UTC timestamps ending in `Z` that omit fractional seconds, returning the corresponding timezone-aware UTC datetime.
- Listing inference endpoints must succeed when endpoint data contains UTC timestamps ending in `Z` without fractional seconds.
