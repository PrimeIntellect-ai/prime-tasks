Better error message when an expression is passed to TableVectorizer or to other expressions
I was writing an example with the expressions, and when I tried to combine them with the TableVectorizer I hit an exception with an error message that wasn't very clear:

```python
from skrub import StringEncoder, TextEncoder
enc = skrub.choose_from({"string": StringEncoder(), "text": TextEncoder()})

TableVectorizer(high_cardinality=enc) # Wrong

import pandas as pd
df = pd.DataFrame({"a": ["a", "b", "c"]})

TableVectorizer(high_cardinality=enc).fit_transform(df)
```

This gives as error message

```

TypeError: Cannot clone object 'choose_from({'string': StringEncoder(), 'text': TextEncoder()})' (type <class 'skrub._expressions._choosing.Choice'>): it does not seem to be a scikit-learn estimator as it does not implement a 'get_params' method.

```

Which makes sense since I'm passing an expression rather than an encoder. I think it may be confusing for users that are learning how to use expressions and the error message is not very clear about waht the error is, so we might want to detect whether the object that is passed is an expression and raise an error accordingly.


Edit to add:

A similar problem happens if I try to define a skrub variable and use another expression as its value. The code should fail early rather than raising an error at the end when I'm crossvalidating the model

### Additional contract requirements

The required behaviour concerns skrub variables. Passing a skrub expression or a skrub choice as the value of a skrub variable must be rejected immediately, when the variable is created, rather than failing later (for example during cross-validation). This applies to `skrub.var()`, `skrub.X()` and `skrub.y()`.

The error raised in that case must be a `TypeError` whose message contains the substring "`value` of a `skrub.var()` must not contain a skrub".
