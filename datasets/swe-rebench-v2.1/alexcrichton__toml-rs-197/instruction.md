allow configuration when encoding to strings
The use case I am trying to meet is the ability to configure `toml` to use tripple quotes (`'''`) when useful (such as when there are any newlines.

Here is some example code:
```
extern crate rustc_serialize;
extern crate toml;

use toml::{encode_str};

#[derive(RustcEncodable)]
struct MyStruct { foo: isize, bar: String }

const LONG_TEXT: &'static str = r#"
this is some text
here is some more
yay
"#;

fn main() {
    let my_struct = MyStruct { foo: 4, bar: LONG_TEXT.to_string() };
    println!("{}", encode_str(&my_struct));
}
```

This currently prints:
```
bar = "\nthis is some text\nhere is some more\nyay\n"
foo = 4
```

I would like for it to be able to print:
```
bar = '''
this is some text
here is some more
yay
'''
foo = 4
```

### Additional contract requirements

The public `toml::Serializer::pretty_string(bool)` setting controls multiline string formatting. When enabled, strings containing newlines are serialized with triple-single-quote delimiters and literal newline characters. When not enabled, multiline strings retain the escaped double-quoted representation.
