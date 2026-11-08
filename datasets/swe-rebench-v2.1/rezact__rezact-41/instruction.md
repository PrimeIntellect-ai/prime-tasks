BUG: JSON.stringify an object with reactive properties does not work as expected
<img width="511" alt="image" src="https://github.com/Rezact/Rezact/assets/2927894/baac5f32-6f25-49ae-8fd1-5c3ded6bc2a2">

### Additional contract requirements

- When `JSON.stringify` is called on an object containing Rezact reactive properties, serialize those properties as their current JSON values at the time of the call. Apply this recursively to nested objects and arrays; do not expose reactive machinery or omit properties because they are reactive.
