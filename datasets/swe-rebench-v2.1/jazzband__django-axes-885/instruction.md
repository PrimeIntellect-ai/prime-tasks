Streamline AXES startup verbose logs
At the moment, the verbose logging starting here: https://github.com/jazzband/django-axes/blob/876b6f3dc4377daa6e1d2a1244ea7a86bf952695/axes/apps.py#L33 emits 3 lines like this:
```
2022-05-07 02:02:21,568 [INFO] axes.apps: AXES: BEGIN LOG
2022-05-07 02:02:21,569 [INFO] axes.apps: AXES: Using django-axes version 5.31.0
2022-05-07 02:02:21,569 [INFO] axes.apps: AXES: blocking by IP only.
```
Would it not be nicer to just output one line? For example like this:
```
2022-05-07 02:02:21,568 [INFO] axes.apps: AXES: BEGIN LOG: version 5.31.0, blocking by IP only
```
I'd be happy to provide a PR if desired.
