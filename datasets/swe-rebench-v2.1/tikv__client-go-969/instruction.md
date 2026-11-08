stale read QPS is too low when test with kv_read_timeout and max_execution_time
# Topology

Version: nightly

```sql
+------+--------------------+--------------------+--------------------------+------------------------------------------+---------------------------+---------------------+-----------+
| TYPE | INSTANCE           | STATUS_ADDRESS     | VERSION                  | GIT_HASH                                 | START_TIME                | UPTIME              | SERVER_ID |
+------+--------------------+--------------------+--------------------------+------------------------------------------+---------------------------+---------------------+-----------+
| tidb | 192.168.78.3:23400 | 192.168.78.3:23080 | 7.4.0-alpha-386-gf1067a1 | f1067a1b761d5bae74510fc715f28814a633352d | 2023-09-13T11:23:19+08:00 | 1h8m5.142420463s    | 634       |
| tidb | 192.168.78.4:23400 | 192.168.78.4:23080 | 7.4.0-alpha-386-gf1067a1 | f1067a1b761d5bae74510fc715f28814a633352d | 2023-09-13T11:23:42+08:00 | 1h7m42.142422497s   | 970       |
| tidb | 192.168.78.2:23400 | 192.168.78.2:23080 | 7.4.0-alpha-386-gf1067a1 | f1067a1b761d5bae74510fc715f28814a633352d | 2023-09-13T11:22:58+08:00 | 1h8m26.1424236s     | 559       |
| pd   | 192.168.78.3:23379 | 192.168.78.3:23379 | 7.4.0-alpha              | 58113f8d17ccec4690445dad2e47cadbacd42da3 | 2023-09-12T15:45:50+08:00 | 20h45m34.142424456s | 0         |
| pd   | 192.168.78.2:23379 | 192.168.78.2:23379 | 7.4.0-alpha              | 58113f8d17ccec4690445dad2e47cadbacd42da3 | 2023-09-12T15:45:50+08:00 | 20h45m34.142425424s | 0         |
| pd   | 192.168.78.4:23379 | 192.168.78.4:23379 | 7.4.0-alpha              | 58113f8d17ccec4690445dad2e47cadbacd42da3 | 2023-09-12T15:45:50+08:00 | 20h45m34.142426465s | 0         |
| tikv | 192.168.80.4:23360 | 192.168.80.4:23380 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142427254s | 0         |
| tikv | 192.168.80.3:23360 | 192.168.80.3:23380 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142427995s | 0         |
| tikv | 192.168.80.2:23361 | 192.168.80.2:23381 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142428715s | 0         |
| tikv | 192.168.80.2:23360 | 192.168.80.2:23380 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142429364s | 0         |
| tikv | 192.168.80.3:23361 | 192.168.80.3:23381 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142431041s | 0         |
| tikv | 192.168.80.4:23361 | 192.168.80.4:23381 | 7.4.0-alpha              | 98eb383b41695b11a03e3d1ce471181f02bfc741 | 2023-09-12T15:45:52+08:00 | 20h45m32.142431848s | 0         |
+------+--------------------+--------------------+--------------------------+------------------------------------------+---------------------------+---------------------+-----------+
```

# Inject network latency

Inject 1000ms network delay in all TiDB nodes to `192.168.80.2`, which deploy TiKV `192.168.80.2:23360` and `192.168.80.2:23361`

```
[root@192.168.78.2]# ping 192.168.80.2
PING 192.168.80.2 (192.168.80.2) 56(84) bytes of data.
64 bytes from 192.168.80.2: icmp_seq=1 ttl=62 time=546 ms
64 bytes from 192.168.80.2: icmp_seq=2 ttl=62 time=217 ms
64 bytes from 192.168.80.2: icmp_seq=3 ttl=62 time=145 ms
64 bytes from 192.168.80.2: icmp_seq=4 ttl=62 time=500 ms
64 bytes from 192.168.80.2: icmp_seq=5 ttl=62 time=1091 ms

[root@192.168.78.2]# ping 192.168.80.3
PING 192.168.80.3 (192.168.80.3) 56(84) bytes of data.
64 bytes from 192.168.80.3: icmp_seq=1 ttl=62 time=0.086 ms
64 bytes from 192.168.80.3: icmp_seq=2 ttl=62 time=0.079 ms
64 bytes from 192.168.80.3: icmp_seq=3 ttl=62 time=0.082 ms


[root@192.168.78.2]# ping 192.168.80.4
PING 192.168.80.4 (192.168.80.4) 56(84) bytes of data.
64 bytes from 192.168.80.4: icmp_seq=1 ttl=62 time=0.088 ms
64 bytes from 192.168.80.4: icmp_seq=2 ttl=62 time=0.072 ms
64 bytes from 192.168.80.4: icmp_seq=3 ttl=62 time=0.058 ms
```

`192.168.78.3` and `192.168.78.4` are same with upper too.

# Test

Load: stale-read request
tidb_kv_read_timeout: 100
max_execution_time: 400

```shell
sysbench --config-file=sysbench.conf mussel_minimal.lua --threads=20 --read_staleness=-10 --kv_read_timeout=100 --max_execution_time=400 --mysql-ignore-errors=all run
```

The following are related metrics, some of metrics here are not as expected:

- Too much failed query in TiDB `192.168.78.2`, which cause by execution timeout.

<img width="1425" alt="image" src="https://github.com/tikv/client-go/assets/26020263/8c6267c0-a68d-4188-b40d-4f7d67566c7e">

<img width="1431" alt="image" src="https://github.com/tikv/client-go/assets/26020263/9cc645e8-8569-4f4c-a6b6-bd65caa6ca94">

<img width="1429" alt="image" src="https://github.com/tikv/client-go/assets/26020263/f5e22871-8956-4f30-a076-17b7abeeb3e5">

<img width="2872" alt="image" src="https://github.com/tikv/client-go/assets/26020263/abf97f28-3268-48d2-b57f-f0a5844cb59e">

### Additional contract requirements

For a stale-read request, a timeout when contacting the leader must not by itself end the request when an eligible follower can serve it. The request must continue to an available follower and must be able to complete successfully within a caller-configured execution-time limit.
