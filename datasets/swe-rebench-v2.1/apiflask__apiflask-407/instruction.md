OpenAPI generation failed with flask_pyoidc
### Discussed in https://github.com/apiflask/apiflask/discussions/405

<div type='discussions-op-text'>

<sup>Originally posted by **EleazarLibelium** February 20, 2023</sup>
Good morning, thank you for the project and for the effort.

I've been using apiflask as the main library for my Rest API for a few months now.

I would like to use it together with the flask extension flask-pyoidc to implement security using keycloak but when I run it and open the url of the API it crashes.

My code is as follows:
main:
```python
import os

import flask
from flask_pyoidc.user_session import UserSession

import config
from flask import jsonify, redirect, Flask
from flask_cors import CORS
from apiflask import APIFlask
from loguru import logger

from src.auth import auth
from src.auth.auth import oidc

# Flask application
application = APIFlask(__name__, docs_path='/swagger/', title='Testing Keycloak Api', version=config.VERSION)
#application = Flask(__name__)

cors = CORS(application, resources={r"*": {"origins": "*"}})
# Flask configuration
application.config['ENV'] = config.ENVIRONMENT_MODE
application.config['SECRET_KEY'] = config.SECRET_KEY
application.config['OIDC_REDIRECT_URI'] = config.REDIRECT_URI
application.config['JSON_SORT_KEYS'] = False
application.config['JSONIFY_PRETTYPRINT_REGULAR'] = True
application.config['OPENAPI_VERSION'] = '3.0.0'


# TODO MAKE THIS WORK!
oidc.init_app(application)


@application.route('/')
@oidc.oidc_auth('default')  # endpoint will require login
def index():
    user_session = UserSession(flask.session)
    return jsonify(access_token=user_session.access_token,
                   id_token=user_session.id_token,
                   userinfo=user_session.userinfo)


if __name__ == "__main__":
    logger.debug('Starting application...')
    logger.debug("Blueprints: {}".format(application.blueprints.items()))
    application.run(config.REST_URL, config.REST_PORT, threaded=True, debug=True)

```

auth:
```python
from flask import jsonify
from loguru import logger
from apiflask import HTTPTokenAuth, APIBlueprint

# FLASK_PYOIDC SECURITY
from flask_pyoidc.provider_configuration import ClientMetadata
from flask_pyoidc.provider_configuration import ProviderConfiguration
from flask_pyoidc import OIDCAuthentication

from src import config

client_metadata = ClientMetadata(client_id=config.CLIENT_ID, client_secret=config.CLIENT_SECRET,
                                 post_logout_redirect_uris=['http://localhost:10011/logout'])

provider_config = ProviderConfiguration(issuer=config.ISSUER,
                                        client_metadata=client_metadata)
oidc = OIDCAuthentication({'default': provider_config})
```

config:
```python
import os

# Application Config
ENVIRONMENT_MODE = os.getenv('ENVIRONMENT_MODE', 'production')
VERSION = os.getenv('VERSION', 'v1.0.0')
SECRET_KEY = os.getenv('SECRET_KEY', 'SUPER-SECRET')

DEVELOPMENT_SERVER = os.getenv("SERVERIP", "localhost")

# Security Config
# PROVIDER & CLIENT
OPENID_REALM = 'test'
ISSUER = os.getenv('ISSUER', f'http://localhost:28080/auth/realms/{OPENID_REALM}')
REDIRECT_URI = os.getenv('REDIRECT_URI', 'http://localhost:10011/api/v1/redirect')
CLIENT_ID = os.getenv('CLIENT_ID', 'test')
CLIENT_SECRET = os.getenv('CLIENT_SECRET', 'test')
SECURE_API = os.getenv('SECURE_API', 'True')
MAX_SESSION_TIME_MINUTES = 1440
SUPER_ADMIN_USERNAME = 'admin'

# GUNICORN CONFIG
REST_URL = os.getenv('REST_URL', '0.0.0.0')
REST_PORT = os.getenv('REST_PORT', '10012')
WEB_UI = os.getenv('WEB_UI', f'http://localhost:{REST_PORT}')
bind = "{}:{}".format(REST_URL, REST_PORT)
workers = 1
threads = 4
timeout = 120

```

Error message displayed when running the application and opening the api in the browser.
```bash
/home/eleazar/PycharmProjects/test-project/venv/bin/python /home/eleazar/PycharmProjects/test-project/src/main.py
2023-02-20 14:06:55.433 | DEBUG    | __main__:<module>:33 - Starting application...
2023-02-20 14:06:55.434 | DEBUG    | __main__:<module>:34 - Blueprints: dict_items([('openapi', <Blueprint 'openapi'>)])
WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
 * Running on all addresses (0.0.0.0)
 * Running on http://127.0.0.1:10012
 * Running on http://192.168.1.32:10012
Press CTRL+C to quit
 * Restarting with stat
 * Serving Flask app 'main'
 * Debug mode: on
2023-02-20 14:06:55.905 | DEBUG    | __main__:<module>:33 - Starting application...
2023-02-20 14:06:55.905 | DEBUG    | __main__:<module>:34 - Blueprints: dict_items([('openapi', <Blueprint 'openapi'>)])
 * Debugger is active!
 * Debugger PIN: 230-173-614
127.0.0.1 - - [20/Feb/2023 14:06:58] "GET /swagger/ HTTP/1.1" 200 -
127.0.0.1 - - [20/Feb/2023 14:06:58] "GET /openapi.json HTTP/1.1" 500 -
Traceback (most recent call last):
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask/app.py", line 2551, in __call__
    return self.wsgi_app(environ, start_response)
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask/app.py", line 2531, in wsgi_app
    response = self.handle_exception(e)
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask_cors/extension.py", line 165, in wrapped_function
    return cors_after_request(app.make_response(f(*args, **kwargs)))
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask/app.py", line 2528, in wsgi_app
    response = self.full_dispatch_request()
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask/app.py", line 1825, in full_dispatch_request
    rv = self.handle_user_exception(e)
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask_cors/extension.py", line 165, in wrapped_function
    return cors_after_request(app.make_response(f(*args, **kwargs)))
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/flask/app.py", line 1823, in full_dispatch_request
    rv = self.dispatch_request()
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/apiflask/app.py", line 446, in dispatch_request
    return view_function(*req.view_args.values())  # type: ignore
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/apiflask/app.py", line 601, in spec
    response = jsonify(self._get_spec('json'))
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/apiflask/app.py", line 687, in _get_spec
    self._spec = self._generate_spec().to_dict()
  File "/home/eleazar/PycharmProjects/test-project/venv/lib/python3.8/site-packages/apiflask/app.py", line 938, in _generate_spec
    [HIDDEN]
AttributeError: 'method' object has no attribute '_spec'

```

Am I making a mistake? If there is a way to do this that I am not currently able to see, please show me how.
</div>

### Additional contract requirements

- OpenAPI generation must succeed when an application has a route registered to a bound-method view, including routes registered by extensions.
