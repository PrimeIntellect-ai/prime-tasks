ui.image() source does not auto-create route to local image when using binding
### Description

```py
a = { 'a': '/home/kon/Pictures/DSC06478.JPG'}

ui.image().bind_source_from(a, 'a')
```

Will throw error:
```
http://127.0.0.1:8080/home/kon/Pictures/DSC06478.JPG not found
```

Same is true if source is set with `img1.source = some_local_path`.
