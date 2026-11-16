In version 3.15.0, when accessing SplObjectStorage by index (object), an error is generated
```
{% for q in sections[s] %}
```
where section is SplObjectStorage
and s is a object
Raise error  An exception has been thrown during the rendering of a template ("Object of class App\Attempt\Section could not be converted to string").
