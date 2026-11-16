Initializing via AutoImageProcessor before AutoProcessor is imported causes `AttributeError`
### System Info

- `transformers` version: 4.45.2
- Platform: Linux-4.18.0-513.18.1.el8_9.x86_64-x86_64-with-glibc2.28
- Python version: 3.10.4
- Huggingface_hub version: 0.24.5
- Safetensors version: 0.4.4
- Accelerate version: 0.33.0
- Accelerate config:    not found
- PyTorch version (GPU?): 2.4.0+cu121 (False)
- Tensorflow version (GPU?): not installed (NA)
- Flax version (CPU?/GPU?/TPU?): not installed (NA)
- Jax version: not installed
- JaxLib version: not installed
- Using distributed or parallel set-up in script?: No

### Who can help?

Probably @zucchini-nlp @amyeroberts, and @qubvel

### Information

- [ ] The official example scripts
- [X] My own modified scripts

### Tasks

- [ ] An officially supported task in the `examples` folder (such as GLUE/SQuAD, ...)
- [ ] My own task or dataset (give details below)

### Reproduction

There seems to be an edge-case in the loading behavior that can sometimes be hit if something is initialized with `from_pretrained` through `AutoImageProcessor` before `AutoProcessor` is imported, and then `from_pretrained` is used on `AutoProcessor`.

Repro case - this works as expected
```python
model_name = "microsoft/Phi-3.5-vision-instruct"
from transformers import AutoImageProcessor
from transformers import AutoProcessor
AutoImageProcessor.from_pretrained(model_name, trust_remote_code=True)
AutoProcessor.from_pretrained(model_name, trust_remote_code=True)
```

But this breaks:
```python
model_name = "microsoft/Phi-3.5-vision-instruct"
from transformers import AutoImageProcessor
AutoImageProcessor.from_pretrained(model_name, trust_remote_code=True)

from transformers import AutoProcessor
AutoProcessor.from_pretrained(model_name, trust_remote_code=True)
```
with `AttributeError: module transformers has no attribute Phi3VImageProcessor`.

I've tried to reproduce this with a few other models, but haven't been able to yet. It is also probably worth noting that the `AutoProcessor` doesn't return the same class as `AutoImageProcessor` for this model, which might matter

### Expected behavior

`AutoImageProcessor` / `AutoProcessor ` `from_pretrained` should have the same behavior if possible, regardless of import and invocation order

### Additional contract requirements

- A processor class declares the classes of its subcomponents (image processor, feature extractor, tokenizer) by name. `AutoProcessor.from_pretrained` must resolve and instantiate those subcomponents even when the declared classes are custom classes that are not exposed as attributes of the top-level `transformers` module, as long as they have been registered with the matching auto-class registration method: `AutoImageProcessor.register`, `AutoFeatureExtractor.register` or `AutoTokenizer.register`. Custom processors are registered with `AutoProcessor.register`.
