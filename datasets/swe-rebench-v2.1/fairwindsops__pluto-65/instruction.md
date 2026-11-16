detect-helm reports no error if API is unreachable
We should definitely get an error for this instead:

```
$ kubectl get no
The connection to the server 127.0.0.1:32768 was refused - did you specify the right host or port?
$ pluto detect-helm --helm-version 2
There were no apiVersions found that match our records.
$ pluto detect-helm --helm-version 3
There were no apiVersions found that match our records.
```
