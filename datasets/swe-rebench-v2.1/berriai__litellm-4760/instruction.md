[Bug]: MedLM (-large and -medium) are missing from cost map
### What happened?

We are trying to access medlm-large and medlm-medium for our work and cannot track cost.

### Relevant log output

```shell
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
~/anaconda3/envs/gemini_pro_finetuning/lib/python3.12/site-packages/litellm/utils.py in ?(model, custom_llm_provider)
   4832             )
   4833     except Exception:
-> 4834         raise Exception(
   4835             "This model isn't mapped yet. model={}, custom_llm_provider={}. Add it here - https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json".format(

ValueError: This model isn't mapped yet. Add it here - https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json

During handling of the above exception, another exception occurred:

Exception                                 Traceback (most recent call last)
/var/folders/v2/cl_z_9bx5mz8qtl6bpf_qnc00000gn/T/ipykernel_60711/2098188452.py in ?()
      1 from litellm import get_model_info
      2
----> 3 get_model_info("medlm-large", "vertex_ai")

~/anaconda3/envs/gemini_pro_finetuning/lib/python3.12/site-packages/litellm/utils.py in ?(model, custom_llm_provider)
   4830                     "supports_response_schema", None
   4831                 ),
   4832             )
   4833     except Exception:
-> 4834         raise Exception(
   4835             "This model isn't mapped yet. model={}, custom_llm_provider={}. Add it here - https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json".format(
   4836                 model, custom_llm_provider
   4837             )

Exception: This model isn't mapped yet. model=medlm-large, custom_llm_provider=vertex_ai. Add it here - https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
```

Steps to recreate (We are getting this error from a completion call but this is the part of the code that litellm calls internally due to which we are getting this error):
```
from litellm import get_model_info

model_info = get_model_info(model="medlm-large")
model_info = get_model_info(model="medlm-medium")
```

### Additional contract requirements

Completion-cost lookup must recognize both `medlm-medium` and `medlm-large`. Their estimates must account for prompt usage, so a substantially longer prompt results in a higher estimate than a shorter prompt.

`get_model_info` lookup must succeed for both `medlm-large` and `medlm-medium`.
