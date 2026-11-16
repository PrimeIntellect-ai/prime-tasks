Kino.Input.utc_datetime uses DateTime.compare to compare NaiveDateTime values
_Found while working on #327, thanks to `ElixirLS Dialyzer`._

Turns out that passing any option to `Kino.Input.utc_datetime` will cause a `FunctionClauseError (no function clause matching in DateTime.compare/2)`.
