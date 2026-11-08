Parsing of some post form data fails on empty fields
Some post form data containing empty field values fail to be parsed correctly, even though they are parsed successfully with other frameworks like python cgi or multiport. The problem is with such data (multiline for legibility):

```
--foo\r\n
Content-Type: text/plain; charset="UTF-8"\r\n
Content-Disposition: form-data; name=empty\r\n
\r\n
--foo\r\n
Content-Type: text/plain; charset="UTF-8"\r\n
Content-Disposition: form-data; name=text\r\n
\r\n
Some Text\r\n
--foo--
```

The field "empty" is indeed left empty. It's unclear from the RFC if it should be followed by 1 or 2 CRLF before the next field. Browsers usually use 2 CRLF, but the Google App Engine uses only 1 for data posted internally. The code below shows the difference between cgi, multipart and werkzeug in this case.

```
from io import BytesIO
from werkzeug.formparser import parse_form_data
import cgi
import multipart

data = b'--foo\r\nContent-Type: text/plain; charset="UTF-8"\r\nContent-Disposition: form-data; name=empty\r\n\r\n--foo\r\nContent-Type: text/plain; charset="UTF-8"\r\nContent-Disposition: form-data; name=text\r\n\r\nSome Text\r\n--foo--'

environ = {'CONTENT_LENGTH': str(len(data)),
        'CONTENT_TYPE': 'multipart/form-data; boundary="foo"',
        'REQUEST_METHOD': 'POST',
        'boundary': b'foo'}

print('### werkzeug')
environ['wsgi.input'] = BytesIO(data)
stream, form, files = parse_form_data(environ)
for k, v in form.items():
    print({'field': k, 'value': v})
print('###')

print('### cgi: ')
stream = BytesIO(data)
print(cgi.parse_multipart(stream, environ))
print('###')

print('### multipart')
environ['wsgi.input'] = BytesIO(data)
(form, files) = multipart.parse_form_data(environ)
for k, v in form.items():
    print({'field': k, 'value': v})
print('###')
```

Output:
```
### werkzeug
{'field': 'empty', 'value': '--foo\r\nContent-Type: text/plain; charset="UTF-8"\r\nContent-Disposition: form-data; name=text\r\n\r\nSome Text'}
###
### cgi:
{'text': ['Some Text'], 'empty': ['']}
###
### multipart
{'field': 'empty', 'value': ''}
{'field': 'text', 'value': 'Some Text'}
###
```

As you can see, werkzeug thinks that the value of the empty field is the boundary and what follows as it apparently expects 2 CRLF. Other frameworks correctly return both values, empty and not empty.

Environment:

- Python version: 3.11
- Werkzeug version: 2.2.3
