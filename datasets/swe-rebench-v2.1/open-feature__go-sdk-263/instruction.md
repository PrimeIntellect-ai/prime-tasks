[BUG] Awkward usage when trying to evaluate a boolean flag in a complex conditional
### Observed behavior

(Related to #259, but that one was closed, so filing this instead)

I just ran into a papercut when working on an experiment to move from an in-house feature management system to OpenFeature. The previous system allowed calling a simple `IsEnabled(flag string) bool` method, which I'd like to replace with a call to `client.BooleanValue`. Mostly this works fine, but I just ran into an awkward case for some code with a fairly convoluted conditional:

```go
if cond1 && (cond2 || (cond3 && features.IsEnabled(ctx, "myflag"))) {
...
```

In this case it's impossible to simply replace the `features.IsEnabled` call with `client.BooleanValue` due to the `err` return value. And I'd rather avoid evaluating the flag altogether if `cond1` is false.

This isn't insurmountable, but it does make it more awkward to use OpenFeature in this case, and will cause adoption friction.

### Expected Behavior

The package should be less awkward to integrate with an existing project.

Could an additional set of methods be considered like these?

```go
func (c *Client) MustBoolean(ctx context.Context, flag string, defaultValue bool, evalCtx EvaluationContext, options ...Option) bool

func (c *Client) MustFloat(ctx context.Context, flag string, defaultValue float64, evalCtx EvaluationContext, options ...Option) float64

func (c *Client) MustInt(ctx context.Context, flag string, defaultValue int64, evalCtx EvaluationContext, options ...Option) int64

func (c *Client) MustObject(ctx context.Context, flag string, defaultValue interface{}, evalCtx EvaluationContext, options ...Option) interface{}

func (c *Client) MustString(ctx context.Context, flag string, defaultValue string, evalCtx EvaluationContext, options ...Option) string
```

### Steps to reproduce

(See above)

### Additional contract requirements

Provide convenience flag-evaluation methods for boolean, float, integer, object, and string values. Each method returns the evaluated value directly rather than an error tuple. If evaluation fails, it returns the caller-supplied default value.
Successful evaluations return the value supplied by the provider, rather than the caller's default, for each convenience method.
