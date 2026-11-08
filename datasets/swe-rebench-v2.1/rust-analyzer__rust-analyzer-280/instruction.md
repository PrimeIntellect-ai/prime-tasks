Bug: operator precedence around **as** keyword is wrong
Hi, I just tried the vscode plugin with the language server, and I had a great experience until now! Congrats for the great project!

**About the bug:**

I opened one of my projects, and immediately in my lib.rs I got a syntax error from the language server. I checked, if the error was valid by compiling the crate, but rustc does not issue any warnings or errors about this specific line of code.

Here is an example I created: [playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=0ef147647f513864accc5ccfec141eb7).

You can try it on the playground, it compiles. If I run the following command with **ra_cli**, I get some syntax errors:

```
 > ra_cli parse < bug.rs | grep err
-------------------------------------
parsing: 237.974µs
                err: `expected COMMA`
                err: `expected SEMI`
          err: `expected SEMI`
          err: `expected expression`
  err: `expected an item`
  err: `expected an item`
```
The error seems to be only about line 7 in the example code. I think something about the + operator might mess up operator precedence, or something else in the parser. My second guess is, that the `as u32` syntax is interpreted as something like `as {TypeParamBounds}`, and the + operator is part of the type / lifetime bounds for some reason. Link to the relevant section in the reference: [Type expressions](https://doc.rust-lang.org/reference/types.html#type-expressions).

**Update:**
Found same parsing bug in one of the files in this repository: [mock_analysis.rs#L76](https://github.com/rust-analyzer/rust-analyzer/blob/8d42deeac354d1f8297d6c4d52b2707fb8d7a771/crates/ra_analysis/src/mock_analysis.rs#L76)
