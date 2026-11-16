Include title Template
# Feature Request
Include title template which can be appended before or after every title if defined.
example config
```javascript
{
  title: "This is a test title.",
  titleTemplate: "Next SEO | %s"
}
```

and the output will be
```html
<title>Next SEO | This is a test title.</title>
```

`%s` will be replaced by the title, so depending on the position, that's where the title will be appended.
