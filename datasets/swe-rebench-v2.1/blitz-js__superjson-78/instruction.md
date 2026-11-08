Serialize Error?
Hi folks! I thought I'll drop this small feature request.

The dreamlike thing I'd like to do is deserializing backend error and throwing it to a React ErrorBoundary.

Currently I get this:

> SerializableError: Error serializing `.json.error` returned from `getServerSideProps` in "/meetings".
> Reason: `object` ("[object Error]") cannot be serialized as JSON. Please only return JSON serializable data types.

### Additional contract requirements

- For `{ e: new Error('epic fail') }`, serialization must include `name: 'Error'`, `message: 'epic fail'`, and a `stack` beginning with `Error: epic fail\n    at Suite.` in the serialized `e` value, and annotate `e` as `['Error']` under `values`.
