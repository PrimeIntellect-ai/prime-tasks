Registry server: updates to existing resources incorrectly abort
This script consistently produces two errors.

```
#!/bin/sh
registry rpc admin delete-project --name projects/test --force

registry rpc admin update-project --project.name=projects/test --allow_missing
registry rpc admin update-project --project.name=projects/test --allow_missing

registry rpc update-api --api.name=projects/test/locations/global/apis/a --allow_missing
registry rpc update-api --api.name=projects/test/locations/global/apis/a --allow_missing
```

The second `update-project` call fails with this message:
```
Error: rpc error: code = Aborted desc = rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "projects_pkey"
```

The second `update-api` also fails with a similar message, but is repeatedly (and unsuccessfully) retried by the GAPIC, which is configured to retry methods of the `Registry` service, until we get this failure:
```
Error: context deadline exceeded
```

The server logs show the problem:
```
  INFO[0117] Handling request.         method=DeleteProject request_id=2e9196ee resource=projects/test
  INFO[0117] Success.                  duration=9.394589ms method=DeleteProject request_id=2e9196ee resource=projects/test status_code=OK
  INFO[0117] Handling request.         method=UpdateProject request_id=502e2636
  INFO[0117] Success.                  duration=3.740473ms method=UpdateProject request_id=502e2636 resource=projects/test status_code=OK
  INFO[0117] Handling request.         method=UpdateProject request_id=8b5dc188
 ERROR[0117] Aborted.                  duration=924.63µs error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "projects_pkey" method=UpdateProject request_id=8b5dc188 status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=aa0f5504
  INFO[0118] Success.                  duration=4.140671ms method=UpdateApi request_id=aa0f5504 resource=projects/test/locations/global/apis/a status_code=OK
  INFO[0118] Handling request.         method=UpdateApi request_id=e0330ef6
 ERROR[0118] Aborted.                  duration=1.165076ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=e0330ef6 status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=b58a4ded
 ERROR[0118] Aborted.                  duration=1.571125ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=b58a4ded status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=2acbedfe
 ERROR[0118] Aborted.                  duration=1.488233ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=2acbedfe status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=cdc4f756
 ERROR[0118] Aborted.                  duration=1.39005ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=cdc4f756 status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=90881969
 ERROR[0118] Aborted.                  duration=1.643127ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=90881969 status_code=Aborted
  INFO[0118] Handling request.         method=UpdateApi request_id=5997e052
 ERROR[0118] Aborted.                  duration=1.545654ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=5997e052 status_code=Aborted
  INFO[0119] Handling request.         method=UpdateApi request_id=19b52751
 ERROR[0119] Aborted.                  duration=1.412112ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=19b52751 status_code=Aborted
  INFO[0120] Handling request.         method=UpdateApi request_id=066ad256
 ERROR[0120] Aborted.                  duration=1.3567ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=066ad256 status_code=Aborted
  INFO[0120] Handling request.         method=UpdateApi request_id=74fcaa91
 ERROR[0120] Aborted.                  duration=1.440423ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=74fcaa91 status_code=Aborted
  INFO[0120] Handling request.         method=UpdateApi request_id=14efe248
 ERROR[0120] Aborted.                  duration=1.39249ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=14efe248 status_code=Aborted
  INFO[0121] Handling request.         method=UpdateApi request_id=a11d0f36
 ERROR[0121] Aborted.                  duration=1.584405ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=a11d0f36 status_code=Aborted
  INFO[0123] Handling request.         method=UpdateApi request_id=a638f662
 ERROR[0123] Aborted.                  duration=1.587956ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=a638f662 status_code=Aborted
  INFO[0126] Handling request.         method=UpdateApi request_id=88f13696
 ERROR[0126] Aborted.                  duration=1.473983ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=88f13696 status_code=Aborted
  INFO[0127] Handling request.         method=UpdateApi request_id=30ecb083
 ERROR[0127] Aborted.                  duration=1.564204ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=30ecb083 status_code=Aborted
  INFO[0128] Handling request.         method=UpdateApi request_id=6af4ed20
 ERROR[0128] Aborted.                  duration=1.450902ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=6af4ed20 status_code=Aborted
  INFO[0133] Handling request.         method=UpdateApi request_id=663d402d
 ERROR[0133] Aborted.                  duration=1.663167ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=663d402d status_code=Aborted
  INFO[0137] Handling request.         method=UpdateApi request_id=fb59509d
 ERROR[0137] Aborted.                  duration=1.586835ms error=rpc error: code = AlreadyExists desc = pq: duplicate key value violates unique constraint "apis_pkey" method=UpdateApi request_id=fb59509d status_code=Aborted
```
