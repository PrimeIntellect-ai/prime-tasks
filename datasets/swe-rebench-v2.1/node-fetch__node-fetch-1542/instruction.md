non-standard HTTP methods are not uppercased by Chrome
<!--- Provide a clear and concise description of what the bug is. -->

**Reproduction**

Steps to reproduce the behavior:
In the browser (Google Chrome), run this code from the console then look at the request in the Dev Tools Network tab

```js
fetch('aoeu.jpg', {method: 'weirdMETHOD'})
```

It'll show

```
Request Method: weirdMETHOD
```

but
```
fetch('aoeu.jpg', {method: 'post'})
```

will send `POST`.

But if you run the same code with `node-fetch`, it'll send `WEIRDMETHOD`

```js
import fetch from 'node-fetch';
fetch('http://localhost:8888/', {method: 'weirdMETHOD'});
```
```
nc -kl 8888
```

will show

```
WEIRDMETHOD / HTTP/1.1
```

**Expected behavior**

`node-fetch` will behave the same way as Chrome's `fetch()`

**Your Environment**

<!--- Include as many relevant details about the environment you experienced the bug in -->

| software         | version
| ---------------- | -------
| node-fetch       | ^3.2.3
| node             |v16.14.2
| npm              |8.5.3
| Operating System |macOS 12.3.1
