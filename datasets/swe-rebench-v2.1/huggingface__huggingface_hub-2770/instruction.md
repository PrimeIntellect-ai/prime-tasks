[HFSummaryWriter] Tags in ModelCardData are None instead of []
### Describe the bug

When the model card is instantiated at [line 182](https://github.com/huggingface/huggingface_hub/blob/8aa1623319f3202972b1f9804fb955cc63f5b133/src/huggingface_hub/_tensorboard_logger.py#L182), the tags in modelcard.data are treated as null instead of an empty list.

As a result, when attempting to add the hf-summary-writer tag at [line 184](https://github.com/huggingface/huggingface_hub/blob/8aa1623319f3202972b1f9804fb955cc63f5b133/src/huggingface_hub/_tensorboard_logger.py#L184), the script crashes.

A simple and easy fix is to [HIDDEN].


### Reproduction

from huggingface_hub import HFSummaryWriter

logger = HFSummaryWriter(
    repo_id="test",
    logdir="/tmp/test/runs",
    commit_every=5
)

### Logs

```shell
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
Cell In[2], line 3
      1 from huggingface_hub import HFSummaryWriter
----> 3 logger = HFSummaryWriter(
      4     repo_id="test",
      5     logdir="/tmp/test/runs",
      6     commit_every=5
      7 )

File ~/miniconda3/envs/dinovdeau_env/lib/python3.12/site-packages/huggingface_hub/_tensorboard_logger.py:186, in HFSummaryWriter.__init__(self, repo_id, logdir, commit_every, squash_history, repo_type, repo_revision, repo_private, path_in_repo, repo_allow_patterns, repo_ignore_patterns, token, **kwargs)
    183     card = ModelCard("")
    185 tags = card.data.get("tags", [])
--> 186 if "hf-summary-writer" not in tags:
    187     tags.append("hf-summary-writer")
    188     card.data["tags"] = tags

TypeError: argument of type 'NoneType' is not iterable
```

### System info

```shell
- huggingface_hub version: 0.27.1
- Platform: Linux-6.8.0-51-generic-x86_64-with-glibc2.39
- Python version: 3.12.7
- Running in iPython ?: No
- Running in notebook ?: No
- Running in Google Colab ?: No
- Running in Google Colab Enterprise ?: No
- Token path ?: /home/bioeos/.cache/huggingface/token
- Has saved token ?: True
- Who am I ?: groderg
- Configured git credential helpers:
- FastAI: N/A
- Tensorflow: N/A
- Torch: 2.5.1
- Jinja2: 3.1.4
- Graphviz: N/A
- keras: N/A
- Pydot: N/A
- Pillow: 11.0.0
- hf_transfer: N/A
- gradio: N/A
- tensorboard: 2.6.2.2
- numpy: 2.1.2
- pydantic: N/A
- aiohttp: 3.10.10
- ENDPOINT: https://huggingface.co
- HF_HUB_CACHE: /home/bioeos/.cache/huggingface/hub
- HF_ASSETS_CACHE: /home/bioeos/.cache/huggingface/assets
- HF_TOKEN_PATH: /home/bioeos/.cache/huggingface/token
- HF_STORED_TOKENS_PATH: /home/bioeos/.cache/huggingface/stored_tokens
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

- Initializing `HFSummaryWriter` with a newly created model card whose tags are `None` must succeed, and the resulting card must include the `hf-summary-writer` tag.
