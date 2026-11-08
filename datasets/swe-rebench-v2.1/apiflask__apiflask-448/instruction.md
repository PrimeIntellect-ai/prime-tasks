Support creating file schema for file response
We support creating file fields via the `apiflask.schemas.File` field class, and use the metadata to set the type and the format:

```python
class ImageIn(Schema):
    image = File()
```

But we still need to support creating the schema for file response. In that case, the whole response is a file, there isn't a key for the file. For example:

```py
paths:
  /report:
    get:
      summary: Returns the report in the PDF format
      responses:
        '200':
          description: A PDF file
          content:
            application/pdf:
              schema:
                type: string
                format: binary
```

I will create a `FileSchema` class that accepts `type` and `format` as arguments, then create the file schema from it. Example usage:

```py
from apiflask.schemas import FileSchema

@app.get('/files/<filename>')
@app.output(FileSchema(type='string', format='binary'), content_type='image/png', description='An image file')
def get_file(filename):
    return ...
```
