Specifying a security scheme always includes a default
<!--
This issue tracker is a tool to address bugs in APIFlask itself. Please use
GitHub Discussion or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->
When overriding the `app.security_schemes` value as defined on https://apiflask.com/authentication/ with a custom key, the `ApiKeyAuth` value is always present. ApiKeyAuth ends up a duplicate of the one I added.

On the docs endpoint, the available authorizations ends up including the unspecified ApiKeyAuth as well as my new key:
<img width="332" alt="Screen Shot 2023-03-01 at 2 43 27 PM" src="https://user-images.githubusercontent.com/46358556/222247968-d816cd11-9197-4026-9b70-711fe93552ef.png">

In the openapi.json file generated, the security schema looks like:
```
"securitySchemes":{"ApiKeyAuth":{"in":"header","name":"X-Example-Key","type":"apiKey"},"api_token":{"in":"header","name":"X-Example-Key","type":"apiKey"}}}
```

A minimal working app that hits this issue:
```py
import typing as t
from flask import current_app
from apiflask import APIFlask, HTTPTokenAuth, Schema, abort
from apiflask.fields import String
from jose import jwt

app = APIFlask(__name__)

auth = HTTPTokenAuth(header="X-Example-Key")

app.security_schemes = {
    "api_token": {"type": "apiKey", "name": "X-Example-Key", "in": "header"},
}

app.config['SECRET_KEY'] = 'secret-key'

class User:
    def __init__(self, id: int, secret: str):
        self.id = id
        self.secret = secret

    def get_token(self):
        header = {'alg': 'HS256'}
        payload = {
            'id': self.id
        }
        return jwt.encode(
            header, payload, current_app.config['SECRET_KEY']
        ).decode()


users = [
    User(1, 'lorem'),
    User(2, 'ipsum'),
    User(3, 'test'),
]


def get_user_by_id(id: int) -> t.Union[User, None]:
    return tuple(filter(lambda u: u.id == id, users))[0]


@auth.verify_token
def verify_token(token: str) -> t.Union[User, None]:
    try:
        data = jwt.decode(
            token.encode('ascii'),
            current_app.config['SECRET_KEY'],
        )
        id = data['id']
        user = get_user_by_id[id]
    except Exception:
        return None
    return user


class Token(Schema):
    token = String()


@app.post('/token/<int:id>')
@app.output(Token)
def get_token(id: int):
    if get_user_by_id(id) is None:
        abort(404)
    return {
        'token': f'Bearer {get_user_by_id(id).get_token()}'
    }


@app.get('/name/<int:id>')
@app.auth_required(auth)
def get_secret():
    return auth.current_user.secret

```

Desired behavior: Specifying a security scheme should only include defined keys. Or there should be some way to exclude ApiKeyAuth. I did find a way to make the UI not display it by adding `"ApiKeyAuth": {}` to the definition, but it still appears as an empty object in the openapi json.

Some additional context - building an API with multiple HTTPAuthToken objects defined with different header values. We want to keep the naming specific and not have a generically named `ApiKeyAuth` value.

Environment:

- Python version: 3.11.0
- Flask version:  2.2.3
- APIFlask version: 1.2.3

### Additional contract requirements

- `HTTPTokenAuth` accepts the public keyword `security_scheme_name` to set a caller-chosen OpenAPI security-scheme name.
- Use that name for both the generated security-scheme component and the operation's security requirement. Multiple token-authentication objects may use distinct names for their different headers, without generating an additional generic `ApiKeyAuth` component for a specifically named object.
