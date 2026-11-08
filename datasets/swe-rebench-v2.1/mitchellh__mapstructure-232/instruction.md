1.4.0: decode hooks receive the wrong type for the `to` argument
I attempted to upgrade from mapstructure 1.3.3 to 1.4.0 in Consul and a few of the test failed.

Debugging one of the tests it seems to be that the decode hook (`reflect.Type` hook) is receiving `map[string]interface {}` as the type of the  `to` argument, where as previously it received `time.Time` as the type of `to`.

Test failures can be seen here: https://app.circleci.com/pipelines/github/hashicorp/consul/15588/workflows/76c7848b-f780-4049-aa5c-f091b737207b/jobs/302146

I suspect the change which added a new `reflect.Value` version of hooks may have broken this. I'll keep looking to see if I can find a fix.

More details:
1. squash is not being used
2. the decode is struct->struct
3. this particular hook is checking the type of both `from` and `to`
3. previously the decode hook would be called twice, now the decode hook is being called 4 times
4. previously it was the second call which receives a from and to of the correct types, now the second call receives the right type for the `from`, and the forth call receives the correct type for `to`. In both cases the other type is `map[string]interface {}`, even though neither the input or output contain a map.

I suspect it is not actually the change to hooks that broke this. It seems like it was one of the changes to `decodeStructFromMap`.

### Additional contract requirements

- In the struct-to-struct case described above, the decode hook must receive the
  correct destination type for `to` (for example `time.Time`), not
  `map[string]interface {}`.
- The struct-to-struct decode must still produce the correct destination value;
  the source value must not be lost.
- When decoding a struct to a map, a field whose type is a pointer to a struct
  is stored in the map as the pointer value itself (for example `&Nested{}`); it
  is not dereferenced into a nested map.
