CIBW_ENVIRONMENT broken in 1.5.3
Somehow, my line of `export CIBW_ENVIRONMENT='... CCACHE_BASEDIR=`python -c "import tempfile; import os; print(os.path.realpath(tempfile.gettempdir()))"` ...'` (see https://github.com/YannickJadoul/Parselmouth/blob/1f3dd9abc63afdf4a1d26db40d210bb4187118a8/.travis.yml#L143; yes, I know I ought to clean this up) breaks:

```
    + /bin/true
    + mkdir -p /project
    + /opt/python/cp38-cp38/bin/python -c 'import sys, json, os; json.dump(os.environ.copy(), sys.stdout)'
    + uname -i
x86_64
    + python -c import 'tempfile;' import 'os;' 'print(os.path.realpath(tempfile.gettempdir()))'
  File "<string>", line 1
    import
```

See https://travis-ci.org/github/YannickJadoul/Parselmouth/jobs/709679114#L392

I'll start investigating, but is this perhaps related to #403, @joerick?
