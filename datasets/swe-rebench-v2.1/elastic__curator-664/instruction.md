Running snapshot action fails when using the snapshot.yml action example.
Run -
curator --config /etc/curator/config/es-host.yml /etc/curator/actions/logstash_snapshot.yml

2016-06-28 11:42:55,842 INFO      Action #1: snapshot
2016-06-28 11:42:55,843 INFO      Starting new HTTP connection (1): es-host.body.stage
2016-06-28 11:42:55,851 INFO      GET http://es-host.body.stage:9200/ [status:200 request:0.008s]
2016-06-28 11:42:55,873 INFO      GET http://es-host.body.stage:9200/_all/_settings?expand_wildcards=open%2Cclosed [status:200 request:0.021s]
2016-06-28 11:42:55,960 INFO      GET http://es-host.body.stage:9200/_cluster/state/metadata

<REMOVED FOR BREVITY>

2016-06-28 11:42:55,985 ERROR     Failed to complete action: snapshot.  <type 'exceptions.KeyError'>: 'creation_date'

[logstash_snapshot.txt](https://github.com/elastic/curator/files/337662/logstash_snapshot.txt)
[es-host.txt](https://github.com/elastic/curator/files/337663/es-host.txt)

### Additional contract requirements

- An index whose settings lack `creation_date` must not appear in the actionable index list.
