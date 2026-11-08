F811 incorrectly raised for type annotation of imported variable
The following piece of code raises F811 error in pyflakes 2.3.0:
```python
        from django.core.files.storage import default_storage
        default_storage: Storage
        file_path = os.path.join(constants.FILE_FIELD_UPLOAD_DIR_NAME, value.name)
        value = default_storage.save(file_path, value)
```

I am using pyflakes with flake8 and getting this output:
```
F811 redefinition of unused 'default_storage' from line 124
        default_storage: Storage
        ^
1     F811 redefinition of unused 'default_storage' from line 124
```

the code works correctly and `default_storage: Storage` does not redefine the variable, and `default_storage` is used two lines below.
