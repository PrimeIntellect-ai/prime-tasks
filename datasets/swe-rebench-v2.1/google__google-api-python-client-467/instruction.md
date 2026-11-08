HttpRequest.__init__ useless mimeparse
Hi,
the code in the `HttpRequest.__init__` is useless:

``` python
    [HIDDEN]
```

And it prevents from `storage.insert` creating explicit dirs without content-type. I.e. [HIDDEN]:

``` python
    api = googleapiclient.discovery.build('storage', 'v1', credentials=credentials)
    media = googleapiclient.http.MediaIoBaseUpload(io.BytesIO(b''), '')
    resp = api.objects().insert(bucket=bucket, name='testdir/', media_body=media).execute()
```

BTW similar code with empty contentType works on the .NET client, too.

### Additional contract requirements

- When a request is executed with `headers={'content-type': ''}`, preserve the explicitly empty value: the outgoing headers must contain `'content-type': ''`.
- An explicit Storage directory insert using a media upload without a content type must not be prevented by `HttpRequest` initialization.
