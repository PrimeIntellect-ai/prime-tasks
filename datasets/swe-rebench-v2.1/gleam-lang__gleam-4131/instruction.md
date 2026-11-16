LSP: Use desugaring code action generates invalid code when there are argument labels
When using argument labels for a function it does not desugar to valid code (should have the label).
```
❯ gleam --version
gleam 1.7.0-rc2
```

![Skärmavbild 2024-12-30 kl  18 27 51](https://github.com/user-attachments/assets/8d0627db-722d-427b-9d89-2748e37ea805)
![Skärmavbild 2024-12-30 kl  18 28 53](https://github.com/user-attachments/assets/4c2550e9-6e56-4d13-baff-b04f5f2a262c)

### Additional contract requirements

- For calls with labelled arguments, preserve the existing arguments in their original order and append the generated callback argument after them with its required label. For example, generate `wibble(two: 2, three: 3, one: fn(a) {`.
- Format the generated calls exactly as follows, keeping the call and callback header on one line and placing the body and closing `})` on the following lines:
```gleam
wibble(one: 1, two: 2, three: fn(a) {
    todo
  })
wibble(1, two: 2, three: fn(a) {
    todo
  })
wibble(1, three: 3, two: fn(a) {
    todo
  })
wibble(two: 2, three: 3, one: fn(a) {
    todo
  })
```
