Candidate.Priority() is completely wrong
https://github.com/pion/ice/blob/7245ac0866456f7c39a534f496d0f346ab7aad30/candidate.go#L212

`^` is XOR in Go, not exponentiation. `2^24 == 26`.

[HIDDEN]

`uint16` is also not large enough to hold the correct value.
