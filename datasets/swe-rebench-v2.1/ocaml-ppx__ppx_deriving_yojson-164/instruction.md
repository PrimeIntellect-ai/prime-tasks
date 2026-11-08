Fails on recursive variant types with the same constructor name
Consider:

```ocaml
type t1 =
  | Foo of int
  | Bar of t2

and t2 =
  | Foo of string
  | Baz of t1
```

Add:

```ocaml
[@@deriving yojson]
```

and you will get:

```
File "_none_", line 1:
Error: This expression has type string but an expression was expected of type
         int
```

coming from the fact, presumably, that the generated pattern matchings both contain a match on `Foo _ ->` and OCaml gets confused typing them. This does not happen if we type explicitly the functions. For instance, the manually written:

```ocaml
let rec t1_to_yojson : t1 -> Yojson.Safe.t = function
  | Foo n -> `List [`String "Foo"; `Int n]
  | Bar x -> `List [`String "Bar"; t2_to_yojson x]

and t2_to_yojson : t2 -> Yojson.Safe.t = function
  | Foo s -> `List [`String "Foo"; `String s]
  | Baz x -> `List [`String "Baz"; t1_to_yojson x]

let rec t1_of_yojson : Yojson.Safe.t -> (t1, string) result = function
  | `List [`String "Foo"; `Int n] -> Ok (Foo n)
  | `List [`String "Bar"; x] -> Result.map (fun x -> (Bar x)) (t2_of_yojson x)
  | _ -> Error "nope"

and t2_of_yojson : Yojson.Safe.t -> (t2, string) result = function
  | `List [`String "Foo"; `String s] -> Ok (Foo s)
  | `List [`String "Baz"; x] -> Result.map (fun x -> (Baz x)) (t1_of_yojson x)
  | _ -> Error "nope"
```

compiles just fine. Note that `ppx_deriving.std` must also be doing something like that because it compiles successfully in this situation.

Tested with `ppx_deriving_yojson` 3.9 and 3.10.

I am happy to write a PR - are they welcome?

I know `ppx_deriving_yojson` isn't maintained so much and `ppx_yojson_conv` should be preferred (although https://github.com/ocaml-ppx/ppx_deriving_yojson/issues/158?), but I'm in a rather big project that has been using `ppx_deriving_yojson` for a long time, and switching would be difficult. (In fact, I even stumbled upon a bug in the OCaml compiler when trying to switch!)
