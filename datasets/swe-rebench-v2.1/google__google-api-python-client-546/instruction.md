Cannot set headers when downloading media
Downloading media with the Google API Python Client is frequently done with the googleapiclient.http.MediaIoBaseDownload class. That class does not seem to respect headers set on HttpRequest objects.

Example:

request = service.objects().get_media(bucket=bucket, object=filename)
request.headers["Cache-Control"] = "no-store"
downloader = http.MediaIoBaseDownload(out_file, request)

What should happen:

Outgoing HTTP requests to download the file should include the header "Cache-Control: no-store".

What does happen:

No Cache-Control header is respected.

One feature of Google Cloud Storage, customer-supplied encryption keys, uses headers to pass those encryption keys around, and so this bug makes downloading encrypted objects difficult.
