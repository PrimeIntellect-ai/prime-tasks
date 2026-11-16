Incorrect Erlang code with block pattern during record update
<!--
Please include the following:
- Steps and code to reproduce the problem
- Versions for Gleam, OS, the runtime and any other software used
- Logs from running Gleam with the `GLEAM_LOG` environment variable set to `trace`
-->
Hi !

I found a funny bug when experimenting with Gleam 1.7.0.
The following code:

```gleam
pub type A {
  A(b: B)
}

pub type B {
  B(c: C)
}

pub type C {
  C(val: Int)
}

pub fn example(a: A) {
  A(..a, b: {
    B(..a.b, c: {
      C(..a.b.c, val: 0)
    })
  })
}
```

Compiles incorrectly to:

```erlang
example(A) ->
    _record = A,
    {a, (_record@1 = erlang:element(2, A),
        {b, (_record@2 = erlang:element(2, erlang:element(2, A)),
            {c, 0})})}.
```

Which is invalid, the `(_record, {` pattern is not working, but when removing the block pattern, like this:

```gleam
pub fn example(a: A) {
  A(..a, b:
    B(..a.b, c:
      C(..a.b.c, val: 0)
    )
  )
}
```

Compiles correctly to:

```erlang
example(A) ->
    _record = A,
    {a,
        begin
            _record@1 = erlang:element(2, A),
            {b,
                begin
                    _record@2 = erlang:element(2, erlang:element(2, A)),
                    {c, 0}
                end}
        end}.
```

It triggers a hard to understand build error looking like (because of a `,` error)

```
project/src/module.gleam: spec for undefined function example/1
%   32|   A(..a, b: B(..a.b, c: { C(..a.b.c, val: 0) }))
%     |  ^
```

---

Edit: I made sure it's working with JS: everything gets compiled as IIFE, so there's no problem.

### Additional contract requirements

- The Erlang generated for the program in the report must be valid Erlang: it must
  compile successfully with the Erlang compiler (`erlc`). The exact textual
  representation of the generated code is not part of the contract.
