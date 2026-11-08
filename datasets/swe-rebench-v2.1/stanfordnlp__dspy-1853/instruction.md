Some typed inputs fail JSON serialization
Context: I have a module that generates a structured output with one program, and then passes that object (a Pydantic model) as an input to the next program.

If the input object contains a field that's not natively JSON serializable (in my example, a `datetime`), a `TypeError` is thrown.

Here's a small example:


```python
import os
import dspy
from datetime import datetime
from pydantic import BaseModel, Field

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "openai/gpt-3.5-turbo")

dspy.configure(
    lm=dspy.LM(
        OPENAI_MODEL,
        api_key=OPENAI_API_KEY,
        cache=False,
    )
)


class Input(BaseModel):
    message: str = Field(desc="The message to be parsed.")

    # This field will cause a failure in the form of a TypeError, since
    # datetimes are not JSON serializable. If you comment this out, the example
    # will work as expected.
    some_datetime: datetime = Field(desc="A random datetime.")


class Output(BaseModel):
    # Output fields work as expected.
    start_at: datetime = Field(desc="The datetime at which the event starts.")
    end_at: datetime = Field(desc="The datetime at which the event ends.")


class Signature(dspy.Signature):
    input: Input = dspy.InputField(desc="A description of the event to be parsed.")
    output: Output = dspy.OutputField(desc="The start and end times of the event.")


event_parser = dspy.Predict(Signature)
result = event_parser(
    input=Input(
        message="My birthday party will be 11/20/2024 from 7pm to 10pm",
        some_datetime=datetime.now(),
    )
)

# The above invocation results in "TypeError: Object of type datetime is not JSON serializable"

print(result.output.model_dump_json(indent=2))
```

### Additional contract requirements

- Provide a public function `format_field_value(field_info, value, assume_text=True)` in the module `dspy.adapters.utils`.
