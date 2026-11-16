add hex and base64 encoding
I'm currently working on a [crypto module](https://github.com/Ma124/tengo/tree/stdlib-crypto) #135 and often you want your encrypted data base64 encoded or your hashes as hex.

Which is why I suggest adding these features to the text module or an encoding module with support for base64 encoding and hex because the only way I known to hex encode bytes at the moment is `sprintf("%x", bin)` which is neither immediately obvious nor efficient.

With some featback from @d5 I can create a pull request.

### Additional contract requirements

Provide an exported `encode` operation that accepts bytes and returns their encoding as text for both hexadecimal and standard Base64. The operation may be exposed from any public standard-library module; no separate decode operation or additional Base64 variants are required.
