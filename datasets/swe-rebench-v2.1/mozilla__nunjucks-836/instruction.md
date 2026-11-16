Bypass autoescape / XSS
The following string works as expected:

``` javascript
var res = nunjucks.renderString('Hello {{ username }}', { username: '<s>Matt</s>' });
console.log(res); //Hello &lt;s&gt;Matt&lt;/s&gt;
```

If however the variable passed to the template is an array autoescape does nothing:

``` javascript
var res = nunjucks.renderString('Hello {{ username }}', { username: ['<s>Matt</s>'] });
console.log(res); // Hello <s>Matt</s>
```

This looks to be intentional https://github.com/mozilla/nunjucks/blob/master/src/runtime.js#L209
However if a autoescape is on any variable that is rendered in a {{ }} block and appended to the output I would expect it to escaped no matter the type.  [HIDDEN]

In express / Koa / (anything else using qs or body-parser) is is trivial to coerce query params types. See the following simple example in express:

``` javascript
var app = express();
var env = nunjucks.configure('views', {
    autoescape: true,
    express: app
});

app.get('/', function(req, res) {
    // This should be fine autoescape is on...
    res.send(nunjucks.renderString('Hello {{ username }}', { username: req.query.name }));
    //res.render('index.html', { username: req.query.name });
});
```
`http://127.0.0.1:3000/?name[]=<script>alert(1)</script>matt`

I created a more detailed writeup and example app at:  https://github.com/matt-/nunjucks_test
