Derive stuck on enum's unit variants that are followed by empty braces or not followed by a comma
When using the derive macros (SerJson, DeJson, SerBin, DeBin, SerRon, DeRon) on an enum, if the last of the variants it's an unit variant not followed by a comma, none of the macros will compile, giving an error message), this means this wouldn't compile:

`#[derive(SerJson, DeJson, SerBin, DeBin, SerRon, DeRon)]`
`enum Message {
    Goodbye,
    Greeting
}`

> message: not implemented: Unexpected type in enum: Type { ident: UnNamed, wraps: None, ref_type: None, as_other: None }

but this would:

`#[derive(SerJson, DeJson, SerBin, DeBin, SerRon, DeRon)]`
`enum Message {
    Goodbye,
    Greeting,
}`

Although if braces are open an unit variant, every macro except SerJson will compile (Where SerJson would give an error message as `message: attempt to subtract with overflow`) , meaning this compiles everything but SerJson:

`#[derive(SerJson, DeJson, SerBin, DeBin, SerRon, DeRon)]`
`enum Message {
    Goodbye,
    Greeting{}
}`

and this too:

`#[derive(SerJson, DeJson, SerBin, DeBin, SerRon, DeRon)]`
`enum Message {
    Goodbye{},
    Greeting,
}`

Also, thanks for this crate!
