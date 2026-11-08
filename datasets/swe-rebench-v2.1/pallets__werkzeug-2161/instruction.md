downloading from send_file unpacks gzipped files
The gzipped files returned with
````
return send_file( fpath, as_attachment=True )
````
are being downloaded unpacked. The file are saved as \*.gz but its content is plaintext.

This does not happen with
Flask==1.1.2
werkzeug==1.0.1

Environment:
- Python version: 3.7.1
- Flask version: 2.0.1
