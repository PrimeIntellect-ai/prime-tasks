[Bug] AzureOpenAI ContentPolicyViolation raising RuntimeError
### What happened?

When a ContentPolicyViolation from AzureOpenAI is triggered, the JSON-Adapter is currently raising a RuntimeError instead of propagating the proper error from litellm, because of a blanket Exception statement in the adapter.

Full Traceback:
```
Traceback (most recent call last):
File "/home/site/wwwroot/validation_script/script.py", line 876, in category_processor
enriched_event = await find_category(
^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/validation_script/script.py", line 949, in find_category
extrakt = await ev_loop.run_in_executor(None, prompt_args["dspy_program"], prompt_input)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/opt/python/3.12/lib/python3.12/concurrent/futures/thread.py", line 58, in run
result = self.fn(*self.args, **self.kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/utils/callback.py", line 326, in sync_wrapper
return fn(instance, *args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/primitives/program.py", line 60, in __call__
return self.forward(*args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/utils/dspy_utils.py", line 154, in forward
response = self.classifier(text=text, lm=llm)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/utils/callback.py", line 326, in sync_wrapper
return fn(instance, *args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/primitives/program.py", line 60, in __call__
return self.forward(*args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/predict/chain_of_thought.py", line 38, in forward
return self.predict(**kwargs)
^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/predict/predict.py", line 85, in __call__
return super().__call__(**kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/utils/callback.py", line 326, in sync_wrapper
return fn(instance, *args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/primitives/program.py", line 60, in __call__
return self.forward(*args, **kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/predict/predict.py", line 157, in forward
completions = adapter(lm, lm_kwargs=config, signature=signature, demos=demos, inputs=kwargs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/adapters/chat_adapter.py", line 51, in __call__
return JSONAdapter()(lm, lm_kwargs, signature, demos, inputs)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
File "/home/site/wwwroot/.python_packages/lib/site-packages/dspy/adapters/json_adapter.py", line 75, in __call__
raise RuntimeError(
RuntimeError: Both structured output format and JSON mode failed. Please choose a model that supports `response_format` argument. Original error: litellm.BadRequestError: litellm.ContentPolicyViolationError: litellm.ContentPolicyViolationError: AzureException - The response was filtered due to the prompt triggering Azure OpenAI's content management policy. Please modify your prompt and retry. To learn more about our content filtering policies please read our documentation: https://go.microsoft.com/fwlink/?linkid=2198766
```

I believe it would be better to simply propagate the ContentViolationError from litelllm in these cases and let it be handled through application logic, as in our case e.g. we would like to flag cases like these and remove them from further processing.

### Steps to reproduce

Simply run any harmful prompt through AzureOpenAI. In our case we are using the following general structure for the module:

```python
    class GeneralModule(dspy.Module):

        def __init__(self):
            super().__init__()
            self.classifier = dspy.ChainOfThought(signature, **predictor_config)

        def forward(self, text, retry_count: int = 0):
            try:
                response = self.classifier(text=text, lm=llm)
            except AttributeError as e:
                raise ValueError("empty response from Azure OpenAI") from e
            except RateLimitError as e:
                # pylint: disable-next=no-member
                if (retry_after := int(e.litellm_response_headers.get("Retry-After", 60))) > 0:
                    logger.warning("Rate limited. Retrying in %d seconds.", retry_after)
                    time.sleep(retry_after)

                if retry_count < 5:
                    return self.forward(text, retry_count + 1)

                raise ValueError("Rate limit exceeded") from e
            except ContentPolicyViolationError as e:
                raise ValueError(f"Content Policy Violation: {e.message}") from e

            return response
```

But the exception handler for ContentPolicyViolation would never trigger since its intercept in the adapter

### DSPy version

2.6.27
