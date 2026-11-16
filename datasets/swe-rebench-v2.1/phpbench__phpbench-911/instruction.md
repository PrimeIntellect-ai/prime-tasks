Expression: Cannot multiply two unparenthesised array accesses
```
subject_params[0] * subject_params[0]
```

results in:

```
In PrettyErrorEvaluator.php line 69:

  Expected "PhpBench\Expression\Ast\NumberNode" but got "PhpBench\Expression\Ast\ListNode":

      Size: (variant_params[0] * variant_params[0])
                                 --------------


In MainEvaluator.php line 40:

  Expected "PhpBench\Expression\Ast\NumberNode" but got "PhpBench\Expression\Ast\ListNode"
                                                                                            In PrettyErrorEvaluator.php line 69:
```
