Token having a`nbf` claim and cached won't become active
This is the current behavior having problems:

```js
const notBefore = 1000
const token = createSigner({ key: 'secret', notBefore })({ a: 1 })
const verify = createVerifier({ key: 'secret', cache: true })
try {
  verify(token)
} catch (err) { // throws with a 'FAST_JWT_INACTIVE' code, alright
  console.error(err)
}

setTimeout(() => {
  try {
    verify(token)
  } catch (err) { // also throws with 'FAST_JWT_INACTIVE', but should not
    console.error(err)
  }
}, 2000)
```

The fact is current tests are passing because of an uneven behavior for comparing time between cache item and token properties. They use a timestamp where `now === min` so they are able to pass, but will unlikely happen in real life.

```js
[HIDDEN]
```
But:
```js
[HIDDEN]
```

### Additional contract requirements

- A token with an `nbf` claim that was rejected as inactive and cached must verify successfully once the current time reaches or passes its not-before time, provided no other verification failure applies.
