Template error supressed when it's included inside {% if %}
I have a template with an error, i.e. like `bad.html`:

     {% fail %}some output

When I include this file I get a proper error message:

    {% include './bad.html' %}

    Template render error: (backend/src/views/test/include.html)
     Template render error: (backend/src/views/test/bad.html) [Line 1, Column 2]
     unknown block tag: fail

However when I include this file inside an `{% if %}` tag I get no error:

    {% if true %}
    {% include './bad.html' %}
    {% endif %}

The included template just stops rendering at the point of failure, I see neither `some output` nor error message.
