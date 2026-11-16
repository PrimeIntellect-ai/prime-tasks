implement json marshal/unmarshal interface on chain.info
https://golang.org/pkg/encoding/json/#Marshal

currently if a chain.info is naively marshal'ed it looses its public kyber key.
