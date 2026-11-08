Unable to get HMR/ HDR for HTTPS express server - Could not reach Remix dev server at https://localhost:3001
### What version of Remix are you using?

1.16.0

### Are all your remix dependencies & dev-dependencies using the same version?

- [X] Yes

### Steps to Reproduce

Example repo of a new Remix Express app using HTTPS: https://github.com/cliffordfajardo/remix-express-https-hmr/tree/main


## 1. Install dependencies

```sh
npm i
```

## 2. Generate self-signed certs
Since we intend on using HTTPs, we need to create self-signed certificates.
After running the command below, you will be prompted to give answers to the openssl CLI tool that generates the cert `server.key` and `server.cert` file.


```sh
npm run gen-cert

# For details see this small blog post:  https://flaviocopes.com/express-https-self-signed-certificate/
```

## 3. Start the remix app
```sh
## NOTE: you will be prompted to fill in a few values from openssl CLI tool. See: https://flaviocopes.com/express-https-self-signed-certificate/
npm run dev
```

### Expected Behavior

The dev server should be reachable via HTTPS when passing https settings inside of `remix.config.js`
See sample repo: https://github.com/cliffordfajardo/remix-express-https-


```js
/** @type {import('@remix-run/dev').AppConfig} */
module.exports = {
  ignoredRouteFiles: ["**/.*"],
  // appDirectory: "app",
  // assetsBuildDirectory: "public/build",
  // serverBuildPath: "build/index.js",
  // publicPath: "/build/",
  // serverModuleFormat: "cjs",
  serverModuleFormat: "cjs",
  future: {
    unstable_dev: {
      httpScheme: 'https',
      httpHost: 'localhost',
      port: 15001,
    },
    v2_errorBoundary: true,
    v2_meta: true,
    v2_normalizeFormMethod: true,
    v2_routeConvention: true,
  },
};
```

### Actual Behavior

```
> remix dev --no-restart -c "node server.js"

💿 Building...
💿 Built in 609ms
Waiting for app server (52766818)
> node server.js
Remix dev server ready
Express server listening https://localhost:15001
❌ Could not reach Remix dev server at https://localhost:3001
```

### Additional contract requirements

- The `remix dev` help output includes these exact lines:

  ```text
  --tls-key           Path to TLS key (key.pem)
  --tls-cert          Path to TLS certificate (cert.pem)
  ```

- The dev server can be configured with TLS through `remix.config.js` using `future.unstable_dev.tlsKey` (path to the TLS key file) and `future.unstable_dev.tlsCert` (path to the TLS certificate file). When both are set, the dev server serves over HTTPS.
