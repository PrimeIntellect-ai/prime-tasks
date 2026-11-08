[BUG] HF_ENDPOINT not correctly handled in get_hf_file_metadata
### Describe the bug

### Describe the bug

When testing [NanoVLM](https://github.com/huggingface/nanoVLM), I noticed that when xet_file_data is None, `HF_ENDPOINT` works correctly (e.g., for datasets). However, for some models, the metadata response still contains hardcoded `huggingface.co` URLs in `XetFileData.refresh_route`.

Example metadata log :
```
url: https://<HF_ENDPOINT>/HuggingFaceTB/SmolLM2-360M-Instruct/resolve/main/model.safetensors
xet_file_data: XetFileData(
    file_hash='a24f4ebae72bd0ae8ea5962912e838391092a7408702fa7c38291ab61026143e',
    refresh_route='https://huggingface.co/api/models/HuggingFaceTB/SmolLM2-360M-Instruct/xet-read-token/cxx3xx'
)
```

Since HF_ENDPOINT is meant to replace all uses of https://huggingface.co, the client should not be receiving hardcoded huggingface.co URLs in metadata fields.


### Reproduction

_No response_

### Logs

```shell

```

### System info

```shell
- huggingface_hub version: 0.33.0
- Platform: Linux-5.15.0-134-generic-x86_64-with-glibc2.35
- Python version: 3.12.11
```
