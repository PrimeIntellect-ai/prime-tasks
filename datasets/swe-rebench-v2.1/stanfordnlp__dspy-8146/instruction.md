[Bug] Usage tracking does not work with Predict
### What happened?

Using the code sample provided in PR #8014 , I am not able to get usage tracking when replacing ChainOfThought with Predict. It always returns None. See below for simple example.

### Steps to reproduce

```
import dspy

dspy.settings.configure(lm=dspy.LM("openai/gpt-4o-mini", cache=False), track_usage=True)

predict = dspy.Predict("question -> answer")
output = predict(question="What is the capital of France?")
print(output.get_lm_usage())
```

### DSPy version

2.6.22

### Additional contract requirements

- Calling `dspy.Predict` with any positional argument must raise a `ValueError` whose message contains the exact text:

  Positional arguments are not allowed when calling `dspy.Predict`, must use keyword arguments that match your signature input fields. For example: dspy.Predict('question -> answer')(question='What is the capital of France?')
