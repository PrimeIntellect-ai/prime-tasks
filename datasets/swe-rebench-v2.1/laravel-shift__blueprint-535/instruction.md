Unable to generate more than one morphTo
<!-- PLEASE COMPLETE THIS TEMPLATE -->

- Laravel Version: 8.59.0
- PHP Version: 8.0.10
- Blueprint Version: 2.0.0
- Platform: Linux

### Issue:
When I try to generate more than one polymorphic relation on a model, the `morphTo` relation generates in the migration file only one relation (the last one by order) but it is Ok for functions in the generated model.
For example : the folowing draft will generate only _resultable_ in the migration file.

### draft.yaml:
```yaml
models:
 Models\Analysis
  content: string:128
  relationships:
   morphTo: surveyable, resultable

```
