Converting either volume_3d or volume3d results in volume3D making it impossible to decamelize
How to reproduce:
```
console.log(camelcase('volume_3d')); // volume3D
console.log(camelcase('volume3d')); // volume3D
```

this operates under the assumption that decamelizing should return the string to its original decamelized version but I'm not sure how that would be possible for strings in this format.

### Additional contract requirements

- A letter that directly follows a digit is not uppercased when the letter is immediately followed by an underscore (`_`) or a hyphen (`-`). For example, `b2b_registration_request` becomes `b2bRegistrationRequest`, `b2b-registration-request` becomes `b2bRegistrationRequest`, and `b2b_registration_b2b_request` becomes `b2bRegistrationB2bRequest`.
- With the `pascalCase` option, the same input becomes `B2bRegistrationRequest`.
- A letter that directly follows a digit and is not followed by an underscore or hyphen is still uppercased, as before. For example, `h2w` becomes `h2W`, and `a1b` with the `pascalCase` option becomes `A1B`.
- Producing distinct outputs for `volume_3d` and `volume3d` is not required; both may continue to produce `volume3D`.
