`log.warn is not a function` in v3.0.0-pre.7
<!-- Have a question? Join #thelounge on freenode -->

* *Node version:* Node.js 8.11.3 on linux x64
* *The Lounge version:* v3.0.0-pre.7

---

For a reason I can't explain, I got the following right after upgrading to v3.0.0-pre.7:

```
TypeError: log.warn is not a function
    at Object.setHome (/usr/lib/node_modules/thelounge/src/helper.js:126:8)
    at Object.<anonymous> (/usr/lib/node_modules/thelounge/src/command-line/index.js:35:8)
    at Module._compile (module.js:652:30)
    at Object.Module._extensions..js (module.js:663:10)
    at Module.load (module.js:565:32)
    at tryModuleLoad (module.js:505:12)
    at Function.Module._load (module.js:497:3)
    at Module.require (module.js:596:17)
    at require (internal/module.js:11:18)
    at Object.<anonymous> (/usr/lib/node_modules/thelounge/index.js:38:1)
```

That's this line: https://github.com/thelounge/thelounge/blob/master/src/helper.js#L126

My config was indeed saying `"theme": "example"` and, sure enough, after changing it to `"default"`, it started fine, but... why did that even break?!
Possibly related to #2563.

### Additional contract requirements

- Add a public function `getHumanDate()` exported from `src/log.js` (as `module.exports.getHumanDate`). It takes no inputs and returns the current date-time as a string formatted `YYYY-MM-DD HH:mm:ss`.
