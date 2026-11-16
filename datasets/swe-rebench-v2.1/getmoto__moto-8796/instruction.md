Secrets from secretsmanager do not appear in the dashboard
I've been using the [secretsmanager](https://docs.getmoto.org/en/latest/docs/services/secretsmanager.html) mock. When I create a secret, there’s no issue—I can retrieve it using Boto without any errors.
However, in the dashboard at `http://localhost:5000/moto-api/`, the secrets do not appear.
Maybe I'm doing something wrong during the secret creation?

I checked in the `http://localhost:5000/moto-api/data.json`
`secretsmanager`key only contains an empty array.
```json
...
 "secretsmanager": {
    "SecretsManager": [

    ]
  },
...
```

Screenshot :
<img width="1152" alt="Image" src="https://github.com/user-attachments/assets/e47550e7-dfbf-42a7-91ce-3b1951e8586e" />

Code to reproduce :

```python
import boto3
from botocore.client import Config
import os

os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ["AWS_SECURITY_TOKEN"] = "testing"
os.environ["AWS_SESSION_TOKEN"] = "testing"

secret_manager = boto3.client("secretsmanager",
  region_name="eu-west-3" ,
  endpoint_url="http://localhost:5000",
)

secret_manager.create_secret(
    Name='database-secret',
    Description='string',
    KmsKeyId='string',
    SecretBinary=b'bytes',
    SecretString='string',
)

secret_manager.list_secrets(
    MaxResults=10,
    SortOrder='asc'
)
```

Moto version : `motoserver/moto:5.0.27` docker image

### Additional contract requirements

- In the JSON returned by `POST /moto-api/data.json`, created Secrets Manager secrets must appear under `data["secretsmanager"]["FakeSecret"]`, and each entry must have a `name` field set to the secret's name.
