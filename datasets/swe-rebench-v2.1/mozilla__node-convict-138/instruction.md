JSON schema doesn't support built-in type format
```JSON
  // schema.json

  "assets": {
    "doc": "Asset information including path and extension",
    "format": "Array",
    "default": [
      {
        "type": "css",
        "path": "/css",
        "ext": ".css"
      }
    ]
  }
```

```javascript
// config.js
var schema = require('config/schema.json');
var conf = convict(schema);
```

I get the following error:
```
Error: 'assets' uses an unknown format type: Array
```

It looks like `"Array"` being interpreted as a String rather than a built-in type.

Should I be doing this a different way?

### Additional contract requirements

When a schema uses the string name of a supported built-in type as its format (such as `"Array"`), the schema is accepted, and values assigned to that property must satisfy the corresponding built-in type.
