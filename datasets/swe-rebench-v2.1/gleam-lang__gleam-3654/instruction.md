Suggest unwrapping when passing `Result(a, _)` instead of `a`
It would be nice if the compiler could suggest how to deal with a result when it's being used where the wrapped `Ok` value is expected instead. What I mean is:
```gleam
pub fn main() {
  let response =
    request.new()
    |> request.set_host("pokeapi.co")
    |> request.set_path("api/v2/pokemon/ditto")
    |> httpc.send

  parse_response(response)
}

fn parse_response(response: Response(String)) {
  todo
}
```
Have an error that looks like this:
```txt
error: Type mismatch
   ┌─ /Users/giacomocavalieri/Desktop/goto/src/goto.gleam:13:18
   │
13 │   parse_response(response)
   │                  ^^^^^^^^

Expected type:

    Response(String)

Found type:

    Result(Response(String), Dynamic)

Hint: to get a value out of a `Result` you can pattern match on it

    case response {
      Ok(response) -> parse_response(response)
      Error(_) -> todo as "deal with error"
    }
```
We could also have a code action to apply this fix too.

### Additional contract requirements

- For a mismatch where `Int` is expected and `Result(Int, a)` is found, the hint must read:

```txt
Hint: If you want to get a `Int` out of a `Result(Int, a)` you can pattern match
on it:

    case result {
      Ok(value) -> todo
      Error(error) -> todo
    }
```
