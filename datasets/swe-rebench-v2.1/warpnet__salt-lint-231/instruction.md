--exclude does not seem to work since 0.5.0
In my CI I have :
``` bash
find . -name "*.jinja" -o -name "*sls" | xargs --no-run-if-empty salt-lint -x 204,205 --exclude ./common_syslog-ng.sls
```
So I was not notified on lint errors for `common_syslog-ng.sls` file, but since 0.5.0 version I get errors from this file.
If I set image tag to `0.4.2`, normal behaviour is back.
