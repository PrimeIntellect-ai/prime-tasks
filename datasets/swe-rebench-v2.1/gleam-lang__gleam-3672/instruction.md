Shorten the `unknown record field` error message where additional notes are not useful
I have the following code snippet:

```gleam
import gleam/http/request
import gleam/httpc
import gleam/io

pub fn main() {
  let response =
    request.new()
    |> request.set_host("pokeapi.co")
    |> request.set_path("api/v2/pokemon/ditto")
    |> httpc.send

  io.debug(response.body)
}
```

And when I run `gleam build` I get the following error message:

```txt
error: Unknown record field
   ┌─ /Users/giacomocavalieri/Desktop/goto/src/goto.gleam:12:20
   │
12 │   io.debug(response.body)
   │                    ^^^^^ This field does not exist

The value being accessed has this type:

    Result(Response(String), Dynamic)

It does not have any fields.

Note: The field you are trying to access might not be
consistently present or positioned across the custom type's
variants, preventing reliable access. Ensure the field exists
in the same position and has the same type in all variants to
enable direct accessor syntax.
```

I don't think the note is particularly useful here and it makes the error feel a bit too verbose for no real gain: a `Result` has no `.body` field anywhere.

I propose we only ever show the additional note if any of the variants of the type has a field with that name; in that case it might be helpful to point this out:
```gleam
pub type Wibble {
  Wibble(body: Int)
  Wobble(body: String)
  Woo
}

wibble.body
//    ^^^^^ Here it makes sense to have the additional note
```

```gleam
pub type Wibble {
  Wibble(Int)
  Wobble(String)
}

wibble.body
//    ^^^^^ Here the additional note is not quite useful
```
