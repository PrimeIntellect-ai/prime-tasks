`clockTolerance` option for verifier is not considered
Hi there,

When I set `clockTolerance` in `createVerifier`, it does not have any effect.

As a second point, in the documentation it is said that this value is added to the current timestamp.
It is enough to validate the `expiry`, but in my case I would also like it to have effect on the `notBefore` property of the token.

The use case is if a token provider generates a token with `nbf` set at the current time, but the validation server clock is slightly lagging behind (even a couple of seconds), and will cause a token validation error.

I can send a PR fixing the tolerance for both expiry and notBefore if you are interested.

```js
// classic expiry case, fails
const expiresIn = 1000
const token1 = createSigner({ key: 'secret', expiresIn })({ a: 1 })

setTimeout(() => {
  try {
    createVerifier({ key: 'secret', clockTolerance: 50000 })(token1)
  } catch (err) {
    console.error(err)
  }
}, 1000)

// notBefore case, fails as well
const clockTimestamp = Date.now() + 1000
const notBefore = 1
const token2 = createSigner({ key: 'secret', clockTimestamp, notBefore })({ a: 1 })

try {
  createVerifier({ key: 'secret', clockTolerance: 50000 })(token2)
} catch (err) {
  console.error(err)
}
```
