protoparse: zero bytes in comments should be verboten
protoparse is out of sync with protoc in that it allows `0x00` bytes in comments.

This is similar to #442 except it deals with comments.

### Additional contract requirements

- When a `0x00` byte occurs in a line (`//`) or block (`/* ... */`) comment, report the error message `invalid control character`.
