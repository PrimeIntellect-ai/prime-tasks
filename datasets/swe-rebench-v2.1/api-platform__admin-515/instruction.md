Validation errors are shown as "Server communication error"
**API Platform version(s) affected**: 3.4.3

**Description**

I'm trying to submit a form that returns validation errors. The errors are properly highlighted in the form, but the main message says "Server communication error" (which is confusing).

Hydra response has proper fields set:

```
@context: "/api/contexts/ConstraintViolationList"
@type: "ConstraintViolationList"
hydra:title: "An error occurred"
hydra:description: "purchasePrice: A valid number is expected\ncurrentValue: A valid number is expected"
```

**How to reproduce**

Just use Hydra and submit a form with a server-side validation failure.

**Possible Solution**

I think, `hydra:title` (and maybe `hydra:description`) should be used instead of `Server communication error` message. And in general, 4xx statuses are probably not server communication errors.

**Additional Context**

This can be also seen on the official Admin demo:

![image](https://user-images.githubusercontent.com/5462781/197391245-6b337ddd-4a99-47e1-a317-dd5ed1635202.png)

### Additional contract requirements

When the API returns a Hydra error document (for example a `ConstraintViolationList`) containing a `hydra:description` field, the error message must be the value of that `hydra:description` field instead of the generic "Server communication error" message.
