ZINTERSTORE does not store values if the destination is used in intersection
Redis behaviour:
```
redis> ZADD zset1 1 "one"
(integer) 1
redis> ZADD zset1 2 "two"
(integer) 1
redis> ZADD zset2 1 "one"
(integer) 1
redis> ZADD zset2 2 "two"
(integer) 1
redis> ZADD zset2 3 "three"
(integer) 1
redis> ZINTERSTORE zset1 2 zset1 zset2 WEIGHTS 2 3
(integer) 2
redis> ZRANGE zset1 0 -1 WITHSCORES
1) "one"
2) "5"
3) "two"
4) "10"
```
miniredis behaviour:
```
redis> ZADD zset1 1 "one"
(integer) 1
redis> ZADD zset1 2 "two"
(integer) 1
redis> ZADD zset2 1 "one"
(integer) 1
redis> ZADD zset2 2 "two"
(integer) 1
redis> ZADD zset2 3 "three"
(integer) 1
redis> ZINTERSTORE zset1 2 zset1 zset2 WEIGHTS 2 3
(integer) 0
redis> ZRANGE zset1 0 -1 WITHSCORES
(empty array)
```
As you can see, the INTERSTORE command does not store the intersected values into the destination `zset1`, if the destination was also used as one of the ZSTORE argumenets.
