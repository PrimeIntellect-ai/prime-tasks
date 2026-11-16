When a call is disallowed due to a parameter rule, display a different message
### Discussed in https://github.com/spaze/phpstan-disallowed-calls/discussions/154

<div type='discussions-op-text'>

<sup>Originally posted by **eithed** December 19, 2022</sup>
I'd like to disallow different methods, with different messages, dependent upon the number of parameters used. For example, if I've got function:
```
function foo($bar = '', $xyz = ''){}
```

I'd like to display:
- if `foo()` is used anywhere, display `Don't use foo`
- if `foo(*)` is used anywhere, display `Don't use foo with parameter $bar`
- if `foo(*,*)` is used anywhere, display `Don't use foo with parameters $bar and $xyz`

Is this possible at all?</div>

_Maintainer note: I think a param-level message could be added that would override the main message when a call would be disallowed due to disallowed/missing param._

### Additional contract requirements

For function rules, `allowExceptParamsAnyValue` can identify argument positions without restricting their values. When different messages are configured for different argument counts, changing argument values without changing the count must not change which message is displayed.
