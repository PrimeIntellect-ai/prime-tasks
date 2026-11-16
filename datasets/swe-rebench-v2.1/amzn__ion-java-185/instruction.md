Implement empty ordered structs as error
The [spec](https://amzn.github.io/ion-docs/binary.html) requires at least one value in the struct for ordered structs in the binary representation (type descriptor 0xD1).
