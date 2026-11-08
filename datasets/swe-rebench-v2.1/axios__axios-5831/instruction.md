Cannot assign to read only property 'set' of object '[object Object]'  at setHeader
### Describe the bug

Sending a request to a specific link that in response, one of his header names is "Set" will cause an "uncaughtException" that cannot be avoided, even by using interceptors, since the `setHeader` called before the interceptors for the response handling.

```
TypeError: Cannot assign to read only property 'set' of object '[object Object]'\n    at setHeader
(/app/node_modules/axios/dist/node/axios.cjs:1651:30)\n    at /app/node_modules/axios/dist/node/axios.cjs:1656:51\n    at
Object.forEach (/app/node_modules/axios/dist/node/axios.cjs:293:10)\n    at setHeaders
(/app/node_modules/axios/dist/node/axios.cjs:1656:13)\n    at AxiosHeaders.set
(/app/node_modules/axios/dist/node/axios.cjs:1659:7)\n    at new AxiosHeaders
```

### To Reproduce

Send a GET request to the following link: https://my424369.businessbydesign.cloud.sap/sap/public/ap/ui/repository/SAP_UI/HTMLOBERON5/client.html?app.component=/SAP_UI_CT/Main/root.uiccwoc&rootWindow=X&redirectUrl=/sap/public/byd/runtime&slalala=25

You will receive the error mentioned above.

### Code snippet

```js
axios.get('https://my424369.businessbydesign.cloud.sap/sap/public/ap/ui/repository/SAP_UI/HTMLOBERON5/client.html?app.component=/SAP_UI_CT/Main/root.uiccwoc&rootWindow=X&redirectUrl=/sap/public/byd/runtime&slalala=25')
```


### Expected behavior

_No response_

### Axios Version

1.4.0

### Adapter Version

_No response_

### Browser

_No response_

### Browser Version

_No response_

### Node.js Version

18.12.1

### OS

Windows 11

### Additional Library Versions

_No response_

### Additional context/Screenshots

#### Response Headers

![chrome_UdptZcbAHk](https://github.com/axios/axios/assets/21152343/75468974-403c-4573-9632-18c680bada1a)
