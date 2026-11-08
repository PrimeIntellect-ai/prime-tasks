Unexpected 413 - RequestEntityTooLarge response
# Bug
When sending non utf-8 bytes into a form the flask server responds with `413 - RequestEntityTooLarge`. This does not seem like the appropriate http error to return in this case. This happens when using a flask app however it might be a bug in werkzeug.


# Reproduce unexpected behaviour:
app.py:
```py
from flask import *

app = Flask(__name__)

@app.route("/", methods=["GET", "POST"])
def home():
    if request.method == "POST":
        print(request.form["name"])
        print(request.form["email"])

    return render_template("home.html")

if __name__ == "__main__":
    app.run()
```

home.html:
```html
<h1>
    This is home.html
</h1>

<form method="post">

    Name: <input name="name"/>

    <br/><br/>

    Email: <input name="email"/>

    <br/><br/>

    <button type="submit">Submit</button>
</form>
```

bug.py:
```py
import requests


if __name__ == '__main__':
    response1 = requests.post(
        'http://localhost:5000',
        b'\x80',
        headers={'Content-Type':'application/x-www-form-urlencoded', 'Content-Length':str(len(b'\x80'))}
    )
    print("response with only \x80 in content: " + str(response1.status_code) + "\n")
    response2 = requests.post(
        'http://localhost:5000',
        b'name=john&email=doe\x80',
        headers={'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': str(len(b'\x80'))}
    )
    print("response with \x80 added to correctly formatted response in content: " + str(response2.status_code))
```

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Python version: 3.10.12
- Flask version: 3.0.3

### Additional contract requirements

- For `application/x-www-form-urlencoded` request data containing invalid UTF-8 bytes, parsing must produce an empty form without raising an error.
