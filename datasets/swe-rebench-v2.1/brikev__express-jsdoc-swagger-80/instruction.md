[BUG] Errors with empty required properties
**Describe the bug**
When we add a JSON object that we generate with our library into Swagger Editor we see this error.

<img width="702" alt="Screen Shot 2020-07-31 at 19 03 26" src="https://user-images.githubusercontent.com/12685053/89058933-8a5ea100-d360-11ea-8483-94a44ee72866.png">

This is because we always add required key for components value. [HIDDEN]

**To Reproduce**
If you want to reproduce this you can use this JSON file in Swagger Editor.

```js
{
  "openapi": "3.0.0",
  "info": {
    "title": "Albums store",
    "description": "Add your description",
    "license": {
      "name": "MIT",
      "url": ""
    },
    "termsOfService": "",
    "version": "1.0.0"
  },
  "servers": [],
  "paths": {},
  "tags": [],
  "components": {
    "schemas": {
      "Song": {
        "description": "A song",
        "required": [
          "title"
        ],
        "type": "object",
        "properties": {
          "title": {
            "description": "The title",
            "type": "string"
          },
          "artist": {
            "description": "The artist",
            "type": "string"
          },
          "year": {
            "description": "The year",
            "type": "number",
            "format": "double"
          }
        }
      },
      "Author": {
        "description": "Author model",
        "required": [
          "name"
        ],
        "type": "object",
        "properties": {
          "name": {
            "description": "Author name",
            "type": "string"
          },
          "age": {
            "description": "Author age",
            "type": "integer",
            "format": "int64"
          }
        }
      },
      "Album": {
        "description": "Album",
        "required": [],
        "type": "object",
        "properties": {
          "firstSong": {
            "description": "",
            "$ref": "#/components/schemas/Song"
          },
          "author": {
            "description": "",
            "$ref": "#/components/schemas/Author"
          }
        }
      }
    }
  }
}
```

**Expected behavior**
Not having Swagger Editor errors.

**Screenshots**
<img width="702" alt="Screen Shot 2020-07-31 at 19 03 26" src="https://user-images.githubusercontent.com/12685053/89058933-8a5ea100-d360-11ea-8483-94a44ee72866.png">

### Additional contract requirements

- For a generated component schema with no required properties, omit the `required` property rather than emitting an empty array. When required properties are present, retain them in `required`.
