Ability to cancel a running Monkey Script
Was trying to find a way to cancel a running Monkey script (in code directly, not command line based) and I don't see any method to do this properly.

Could there be a possibility of using a Context or something to stop execution in progress?
A change to the [Eval function](https://github.com/skx/monkey/blob/29357e427d852c5c8ef2c628796f35a77d4d3cf8/evaluator/evaluator.go#L30) like below would solve some of the issue (The function would bail after the current operation completes)

```
[HIDDEN]
                [HIDDEN]
                        default:
               }
        //Statements
```

Thanks

### Additional contract requirements

The evaluator exposes `SetContext(ctx context.Context)` to select the context used by subsequent evaluations. If that context is cancelled or reaches its deadline while a Monkey program is running, evaluation stops after the current operation completes and returns an `object.Error` whose `Message` equals the context error's message.
