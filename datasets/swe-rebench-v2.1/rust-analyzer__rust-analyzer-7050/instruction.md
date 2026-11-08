Macro invocation rejected depending on argument order with tt fragment specifier and double equals
In the following reproduction the second invocation of `bar!` where the first argument is the token `==` is rejected by RA with the message `Expected 1 argument, found 0`
However it is accepted by rustc and demonstrates the expected behavior. Something to note is that if the order of the parameters are reversed so that the `path` is provided before the `tt` fragment then RA is satisfied.
https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=860a398473fe04567d86745ac5282c5f

However something else to note is that RA is fine with the order of parameters in the following case
https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=6e0b7b2b9bd36f9e54ed9935cb225dc0

I have RA version `2020-11-30 (ac30710)` on Linux x64 and the client editor is VSCode 1.51.1
