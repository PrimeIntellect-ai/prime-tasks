Allow multiline output in Dynamic vars
There is only one way of setting a multiline variable in task from shell output that I am aware of, and that is using the deprecated `set`.

Using the `sh: program` syntax will (deliberately) give an error. I don't know what the reasoning for that is, but there are many good use cases for _allowing_ multiline variables to be set from a shell command, such as fetching private keys from a keychain. In this case you would also prefer if you didn't need to store the private key in a temp file on disk.
