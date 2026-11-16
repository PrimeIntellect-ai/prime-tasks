AsyncInferenceClient incompatible with vLLM
### Describe the bug

Hi, I've found in latest huggingface_hub (0.29.1), when I was using AsyncInferenceClient to make a request to an vLLM endpoint started with "http://", the model name is hardcoded to "tgi" https://github.com/huggingface/huggingface_hub/blob/v0.29.1/src/huggingface_hub/inference/_providers/hf_inference.py#L87 . However, "tgi" is not recognized by vLLM so it will raise an error said that "tgi" model is not found. I then found that it was caused by https://github.com/huggingface/huggingface_hub/pull/2836 that hardcode to any payload_model to "tgi" that starts with "http*" like prefix.

Is this the expected behavior? Think it would be great if AsyncInferenceClient is compatible to both vLLM/TGI!

### Reproduction

1. start a vLLM server
```bash
export LLM_MODEL_ID=llava-hf/llava-1.5-7b-hf
docker compose up -d
```

compose yaml is as belows

```yaml
services:
  vllm-service:
    image: ${REGISTRY:-opea}/vllm:${TAG:-latest}
    container_name: vllm-service
    ports:
      - ${VLLM_PORT:-11507}:80
    volumes:
      - "./data:/data"
    shm_size: 128g
    environment:
      no_proxy: ${no_proxy}
      http_proxy: ${http_proxy}
      https_proxy: ${https_proxy}
      HF_TOKEN: ${HUGGINGFACEHUB_API_TOKEN}
      LLM_MODEL_ID: ${LLM_MODEL_ID}
      VLLM_TORCH_PROFILER_DIR: "/mnt"
    command: --model $LLM_MODEL_ID --host 0.0.0.0 --port 80 --chat-template examples/template_llava.jinja  # https://docs.vllm.ai/en/v0.5.0/models/vlm.html

networks:
  default:
    driver: bridge
```

2. do test with AsyncInferenceClient

This should work with 0.28.1 but fail with 0.29.1

```py
>>> from huggingface_hub import AsyncInferenceClient
>>> lvm_client = AsyncInferenceClient(f"http://localhost:11507/v1/chat/completions")
>>> img_b64_str = "iVBORw0KGgoAAAANSUhEUgAAADUAAAAlCAYAAADiMKHrAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAKPSURBVHgB7Zl/btowFMefnUTqf+MAHYMTjN4gvcGOABpM+8E0doLSE4xpsE3rKuAG3KC5Ad0J6MYOkP07YnvvhR9y0lVzupTIVT5SwDjB9fd97WfsMkCef1rUXM8dY9HHK4hWUevzi/oVWAqnF8fzLmAtiPA3Aq0lFsVA1fRKxlgNLIbDPaQUZQuu6YO98aIipHOiFGtIqaYfn1UnUCDds6WPyeANlTFbv9WztbFTK+HNUVAPiz7nbPzq7HsPCoKWIBREGfsJXZit5xT07X0jp6iRdIbEHOnjyyD97OvzH00lVS2K5OS2ax11cBXxJgYxlEIE6XZclzdTX6n8XjkkcEIfbj2nMO0/SNd1vy4vsCNjYPyEovfyy88GZIQCSKOCMf6ORgStoboLJuSWKDYCfK2q4jjrMZ+GOh7Pib/gek5DHxVUJtcgA7mJ4kwZRbN7viQXFzQn0Nl52gXG4Fo7DKAYp0yI3VHQ16oaWV0wYa+iGE8nG+wAdx5DzpS/KGyhFGULpShbKEXZQinqLlBK/IKc2asoh4sZvoXJWhlAzuxV1KBVD3HrfYTFAK8ZHgu0hu36DHLG+Izinw250WUkXHJht02QUnxLP7fZxR7f1I6S7Ir2GgmYvIQM5OYUuYBdainATq2ZjTqPBlnbGXYeBrg9Od18DKmc1U0jpw4OIIwEJFxQSl2b4MN2lf74fw8nFNbHt/5N9xWKTZvJ2S6YZk6RC3j2cKpVhSIShZ0mea6caCOCAjyNHd5gPPxGncMBTvI6hunYdaJ6kf8VoSCP2odxX6RkR6NOtanfj13EswKVqEQrPzzFL1lK+YvCFraiEqs8TrwQLGYraqpX4kr/Hixml+63Z+CoM9DTo438AUmP+KyMWT+tAAAAAElFTkSuQmCC"
>>> prompt="What is this?"
>>> import asyncio
>>> asyncio.run(lvm_client.chat.completions.create(model="llava-hf/llava-1.5-7b-hf", messages=[{"role": "user", "content": [{"type": "text", "text": prompt}, {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img_b64_str}"}}]}] ))
```

### Logs

```shell

```

### System info

```shell
Copy-and-paste the text below in your GitHub issue.

- huggingface_hub version: 0.28.1
- Platform: Linux-6.8.0-50-generic-x86_64-with-glibc2.39
- Python version: 3.12.3
- Running in iPython ?: No
- Running in notebook ?: No
- Running in Google Colab ?: No
- Running in Google Colab Enterprise ?: No
- Token path ?: /root/.cache/huggingface/token
- Has saved token ?: False
- Configured git credential helpers: store
- FastAI: N/A
- Tensorflow: N/A
- Torch: 2.6.0
- Jinja2: 3.1.5
- Graphviz: N/A
- keras: N/A
- Pydot: N/A
- Pillow: 11.1.0
- hf_transfer: N/A
- gradio: N/A
- tensorboard: N/A
- numpy: 1.26.4
- pydantic: 2.10.6
- aiohttp: 3.11.11
- ENDPOINT: https://huggingface.co
- HF_HUB_CACHE: /root/.cache/huggingface/hub
- HF_ASSETS_CACHE: /root/.cache/huggingface/assets
- HF_TOKEN_PATH: /root/.cache/huggingface/token
- HF_STORED_TOKENS_PATH: /root/.cache/huggingface/stored_tokens
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

For conversational requests sent to a custom HTTP endpoint, when the caller supplies a model, include that model in the JSON request sent to the endpoint instead of substituting `tgi`.
