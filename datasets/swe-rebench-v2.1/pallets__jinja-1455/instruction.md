containment should only fail for `StrictUndefined`, not regular `Undefined`
### Summary
Hello, I'm looking into a change of behaviour between jinja2-2.11.x (and previous... this section of our template has been around for a long time) and jinja2-3.0.x.  I have a feeling it was a bug in 2.11 that got fixed but since I don't see the behaviour change spelled out in the changelog I decided to report it in case it was an unintended side effect of a different bugfix.

With jinja2-2.11.x, certain `{% if x in dictionary[key] %}` constructs will evaluate False if key is not present in the dictionary.  In jinja2-3.0.x, the construct will raise an UndefinedException instead.

### Reproducer

Here's a small template that triggers the behaviour:
``` jinja
{# Called with d = {'test': {}} #}
Start
{% for entry, value in d.items() %}
{%     if 'n' in value.a %}
    Condition triggered
{%     endif %}
{% endfor %}
End
```
And here's my test script with the template embedded in a python string:
``` python
#!/usr/bin/python3

import jinja2
data = """
{# Called with d = {'test': {}} #}
Start
{% for entry, value in d.items() %}
{%     if 'n' in value.a %}
Condition triggered
{%     endif %}
{% endfor %}
End
"""
t = jinja2.Template(data)
print(t.render(d={'test': {}}))
```

#### Behaviour in 2.11
```


Start



End
```

#### Behaviour in 3.0

```
Traceback (most recent call last):
  File "/srv/ansible/jinja2-3.x-bug/test2.py", line 15, in <module>
    print(t.render(d={'test': {}}))
  File "/home/badger/.local/lib/python3.9/site-packages/jinja2/environment.py", line 1304, in render
    self.environment.handle_exception()
  File "/home/badger/.local/lib/python3.9/site-packages/jinja2/environment.py", line 925, in handle_exception
    raise rewrite_traceback_stack(source=source)
  File "<template>", line 5, in top-level template code
jinja2.exceptions.UndefinedError: 'dict object' has no attribute 'a'
```
### Additional information

I have done a little bit of experimentation and the change is caused by https://github.com/pallets/jinja/pull/1204/ (If I remove that change from a jinja2-3.0.1 install, it reverts to the 2.11.x behaviour).  However, since my template does not traceback with a TypeError in 2.11.x (which is the bug being fixed by that PR: https://github.com/pallets/jinja/issues/1198  ), I'm unsure if the new behaviour is desired or not.

Personally, I feel the new behaviour is more intuitive and want to point it out to people as a reason they should normalize their data before passing it off to be rendered but I just wanted to make sure it was an intended change before I open my big mouth ;-)


Environment:

- Python version: Tested in both 3.9 and 3.8
- Jinja version: 2.11.2 versus 3.0.1
