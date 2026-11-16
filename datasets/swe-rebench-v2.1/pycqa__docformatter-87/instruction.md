Bug: Docformatter incorrectly detects first line as a docstring
Consider this unfortunate construction:
```
def _send_notification(line):
    'email' in line and send_notification(line['email'])
```

docformatter changes it to:
```
 def _send_notification(line):
    """email.""" in line and send_notification(line['email'])
```

I think it should remain unchanged.
