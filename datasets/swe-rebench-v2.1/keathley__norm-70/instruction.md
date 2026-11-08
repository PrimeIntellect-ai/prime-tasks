SpecError does not handle values that are Spec.And or Spec.Or
If a SpecError is raised, it can fail if a value is a Spec.Or or a Spec.And.
For example:
```
import Norm
my_schema  = schema(%{count: spec(is_integer() and &(&1 > 0))})
selection(my_schema, [:incorrect_key])
```
results in:
```
** (FunctionClauseError) no function clause matching in Norm.SpecError.format/2

    The following arguments were given to Norm.SpecError.format/2:

        # 1
        #Norm.Spec<is_integer() and &(&1 > 0)>

        # 2
        1

    Attempted function clauses (showing 8 out of 8):

        defp format({key, spec_or_schema}, i)
        defp format(atom, _) when is_atom(atom)
        defp format(str, _) when is_binary(str)
        defp format(%Norm.Spec{predicate: pred}, _)
        defp format(%Norm.Schema{specs: specs}, i)
        defp format(%Norm.Spec.Collection{spec: spec}, i)
        defp format(%Norm.Spec.Alt{specs: specs}, i)
        defp format(%Norm.Spec.Union{specs: specs}, i)

    (norm) lib/norm/errors.ex:54: Norm.SpecError.format/2
    (norm) lib/norm/errors.ex:62: anonymous fn/2 in Norm.SpecError.format/2
    (elixir) lib/enum.ex:1340: anonymous fn/3 in Enum.map/2
    (stdlib) maps.erl:257: :maps.fold_1/3
    (elixir) lib/enum.ex:1964: Enum.map/2
    (norm) lib/norm/errors.ex:67: Norm.SpecError.format/2
    (norm) lib/norm/errors.ex:48: Norm.SpecError.msg/1
    (norm) lib/norm/errors.ex:42: Norm.SpecError.exception/1
```
The desired behaviour would be a nicely formatted error such as:
```
** (Norm.SpecError) key: :incorrect_key was not found in schema:
%{
  :count => (spec(is_integer()) and spec(&(&1 > 0)))
}

    lib/norm/spec/selection.ex:56: Norm.Spec.Selection.assert_spec!/2
    lib/norm/spec/selection.ex:36: Norm.Spec.Selection.select/3
```

I have made the small fix required to handle these cases [here](https://github.com/NarrativeApp/norm), but have not added tests, check for other cases such as this, or given much thought to how these cases are formatted.
Happy for anyone to take it further and turn it into a PR, or I would be happy to make the change required to submit a PR myself.
