Ethereum validator incorrect checksum validation
- [x] I have looked at the documentation [here](https://pkg.go.dev/github.com/go-playground/validator/v10#section-documentation) first?
- [x] I have looked at the examples provided that may showcase my question [here](/_examples)?

### Package version eg. v9, v10:

V10


### Issue, Question or Enhancement:

The `eth_addr` validation incorrectly passes an invalid checksumed address.

### Code sample, to showcase or reproduce:

```go
package main

import (
	"log"

	"github.com/go-playground/validator/v10"
)

var (
	validate = validator.New()
	s        = "0x000000000000000000000000000000000000dead"
)

func main() {
	err := validate.Var(s, "eth_addr")
	log.Println(err)
}

```

### Additional contract requirements

- The `eth_addr` validation accepts any syntactically valid Ethereum address: a `0x` prefix followed by exactly 40 hexadecimal characters, in any letter case. It does not reject an address because of its checksum.
- A new validation tag `eth_addr_checksum` accepts a value only when it is a syntactically valid Ethereum address and its letter casing matches the EIP-55 checksum. A value whose casing does not match the checksum is rejected, including a value written entirely in lowercase or entirely in uppercase whose casing is not the checksum-correct casing.
