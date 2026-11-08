Applying @skip/@include to Nullable field lead to wrong model
According to [the spec](https://github.com/graphql/graphql-spec/blame/October2021/spec/Section%206%20--%20Execution.md#L487-L489), if `@skip`/`@include` is applied, execution of that field is ignored, thus not producing field in final data.

Using https://beta.pokeapi.co/graphql/console/ and take this example query:

```graphql
{
  pokemon_v2_pokemon(where: {name: {_eq: "pikachu"}}) {
    skipped_notnullable_field: name @skip(if: true)
    skipped_nullable_field: order @skip(if: true)
  }
}
```

And the result would be:

```json
{
  "data": {
    "pokemon_v2_pokemon": [
      {}
    ]
  }
}
```

Thus like #204, the expected code should be:

```python
class GetPokemonPokemonV2Pokemon(BaseModel):
    skipped_notnullable_field: Optional[str] = None
    skipped_nullable_field: Optional[int] = None
```

But the current generated code is:

```python
class GetPokemonPokemonV2Pokemon(BaseModel):
    skipped_notnullable_field: Optional[str] = None
    skipped_nullable_field: Optional[int]
```

Leading to a Pydantic verify error during runtime.

This is a follow up of #204
