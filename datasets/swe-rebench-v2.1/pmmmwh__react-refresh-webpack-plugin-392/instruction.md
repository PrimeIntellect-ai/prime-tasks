webpack-dev-server 4.0.0-beta.3 causes react-refresh-webpack-plugin to crash
Not sure if it's a bug, or even if it's on your side, but just a heads-up, and hopefully some info that could come in handy if people stumble upon the same issue as me.

Updating webpack-dev-server from 4.0.0-beta.2 to 4.0.0-beta.3 caused several of my apps to crash because of react-refresh-webpack-plugin 0.4.3 with the following error:

```
Uncaught DOMException: Failed to construct 'WebSocket': The URL's scheme must be either 'ws' or 'wss'. 'https' is not allowed.
    at new WebsocketClient (webpack:///node_modules/webpack-dev-server/client/clients/WebsocketClient.js?:39:20)
    at Module.initWDSSocket (webpack:///node_modules/@pmmmwh/react-refresh-webpack-plugin/sockets/WDSSocket.js?:24:24)
    at setupOverlay (webpack:///node_modules/@pmmmwh/react-refresh-webpack-plugin/client/ErrorOverlayEntry.js?:86:32)
    at runWithPatchedUrl (webpack:///node_modules/@pmmmwh/react-refresh-webpack-plugin/client/utils/patchUrl.js?:36:3)
    at eval (webpack:///node_modules/@pmmmwh/react-refresh-webpack-plugin/client/ErrorOverlayEntry.js?:82:62)
    at Module./node_modules/@pmmmwh/react-refresh-webpack-plugin/client/ErrorOverlayEntry.js?sockHost=0.0.0.0&sockPort=3001&sockProtocol=https (https://localhost:3001/vendors-node_modules_pmmmwh_react-refresh-webpack-plugin_client_ErrorOverlayEntry_js_sockHost-9da5dc.b56e57f2.js:18:1)
```

Updating react-refresh-webpack-plugin to 0.5.0-beta.7 (to get #242) and configuring it like so:

```diff
    new ReactRefreshWebpackPlugin({
+      overlay: {
+        sockProtocol: 'wss',
+        sockHost: 'localhost',
+      },
    }),
```

causes the app to load again without any errors.

Hardcoding `sockHost`, however, had negative consequences, because now I couldn't use react-refresh on other hosts e.g. for mobile testing. If I didn't hardcode `sockHost` it was resolved to `0.0.0.0` which I have set in `devServer.host`.

Finally, removing `devServer.host` altogether and removing `sockHost` from ReactRefreshWebpackPlugin options cause it all to work again, both locally and remotely.
