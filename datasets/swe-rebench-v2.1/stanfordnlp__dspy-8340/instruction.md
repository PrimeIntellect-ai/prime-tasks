[Bug] History constructs assistant messages without [[ ## completed ## ]] tags.
### What happened?

The DSPy History example produces an incorrectly formatted assistant message.
https://dspy.ai/api/primitives/History/

The System message says the [[ ## answer ## ]] should be followed by [[ ## completed ## ]]. [HIDDEN]


### Steps to reproduce

```
import dspy

dspy.settings.configure(lm=dspy.LM("openai/gpt-4o-mini"))

class MySignature(dspy.Signature):
    question: str = dspy.InputField()
    history: dspy.History = dspy.InputField()
    answer: str = dspy.OutputField()

history = dspy.History(
    messages=[
        {"question": "What is the capital of France?", "answer": "Paris"},
        {"question": "What is the capital of Germany?", "answer": "Berlin"},
    ]
)

predict = dspy.Predict(MySignature)
outputs = predict(question="What is the capital of France?", history=history)

print('System message:')
print(dspy.settings.lm.history[-1]['messages'][0]['content'])
print('Constructed assistant message:')
print(dspy.settings.lm.history[-1]['messages'][2]['content'])
```


```
System message:
Your input fields are:
1. `question` (str)
2. `history` (History)
Your output fields are:
1. `answer` (str)
All interactions will be structured in the following way, with the appropriate values filled in.

[[ ## question ## ]]
{question}

[[ ## history ## ]]
{history}

[[ ## answer ## ]]
{answer}

[[ ## completed ## ]]
In adhering to this structure, your objective is:
        Given the fields `question`, `history`, produce the fields `answer`.
Constructed assistant message:
[[ ## answer ## ]]
Paris
```

[HIDDEN]

Thanks for your excellent work on DSPy!


### DSPy version

2.6.23

### Additional contract requirements

- For ChatAdapter, all assistant messages, including messages for conversation history and few-shot examples, must place `[[ ## completed ## ]]` after the answer content and end with the exact suffix `\n\n[[ ## completed ## ]]\n`.
