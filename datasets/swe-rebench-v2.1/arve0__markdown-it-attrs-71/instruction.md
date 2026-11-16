= in attribute value are removed
When including an `=` in the value of an attribute, the `=` is parsed out. Different escaping mechanisms were ignored (`link='...'` and `\=`).

Example input:
```md
**Bold Link** {link=/some/page/in/app/id=1}
```

Current output:
```html
<p link="/some/page/in/app/id1"><strong>Bold Link</strong></p>
```

Expected output:
```html
<p link="/some/page/in/app/id=1"><strong>Bold Link</strong></p>
```
