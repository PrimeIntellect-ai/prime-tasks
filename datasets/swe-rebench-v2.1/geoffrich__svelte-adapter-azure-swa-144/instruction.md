Dynamically determine node version
https://github.com/geoffrich/svelte-adapter-azure-swa/pull/47 updated the adapter to target Node 16 instead of 12. This is good, but it would be better if we could allow the user to specify which node version to use. Otherwise, they'll be tied to the adapter Node version.

Here's how adapter-vercel does it:

https://github.com/sveltejs/kit/blob/3dae8e702641b5ee762b1892b7b7aa90e1c19a7c/packages/adapter-vercel/index.js#L388-L399

### Additional contract requirements

- When generating the adapter configuration, honor a user-supplied `platform.apiRuntime` value as the Node runtime in the generated configuration.
