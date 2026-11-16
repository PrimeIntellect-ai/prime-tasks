Search does not return key in _yz_rk [JIRA: CLIENTS-908]
When using Riak.Commands.YZ.Search.Builder, I get incorrect `_yz_rk` values. I expect the key of the item, but I get what seems like gibberish. `_yz_id` values are also not what I would expect.

For example, this is one of the returned docs from the node code:

```json
{
  "score": 1,
  "_yz_rb": "ssh-sessions",
  "_yz_rt": "ssh-sessions",
  "_yz_rk": 400000,
  "_yz_id": 1,
  "hardwareId": 2,
  "state": "connected"
}
```

and the corresponding doc returned from a curl request: `curl "http://localhost:8098/search/query/ssh-sessions?wt=json&q=hardwareId:\[0%20TO%20100\]"`

```json
{
  "state": "connected",
  "hardwareId": 2,
  "_yz_id": "1*ssh-sessions*ssh-sessions*4e05ed89-2a49-4f17-8885-ca79f0d292c0*41",
  "_yz_rk": "4e05ed89-2a49-4f17-8885-ca79f0d292c0",
  "_yz_rt": "ssh-sessions",
  "_yz_rb": "ssh-sessions"
}
```

This is in a test environment that has two nodes in a cluster.

I went as far as uninstalling riak from each of these servers, deleting all of /var/lib/riak, reinstalling, and then setting up just this search index with the four dummy values, and it continues to be a problem.

If there's any other information I can provide, let me know. I'm just trying to get spun up on riak development, so I'm not sure what to check or what to try next.

## Additional information

Component|Version
:----|-----:
riak|2.1.4
Ubuntu|14.04.4
basho-riak-client|2.2.1
node|6.2.2


<details>
  <summary>ssh-sessions.xml schema definition</summary>

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<schema name="default" version="1.5">
    <fields>
        <field name="hardwareId" type="long"   indexed="true" stored="true"  multiValued="false"/>
        <field name="state"      type="string" indexed="true" stored="true"  multiValued="false"/>
        <field name="host"       type="string" indexed="true" stored="false" multiValued="false"/>
        <field name="port"       type="int"    indexed="true" stored="false" multiValued="false"/>

        <field name="_yz_id" type="_yz_str" indexed="true" stored="true" multiValued="false" required="true"/>
        <!-- Entropy Data: Data related to anti-entropy -->
        <field name="_yz_ed" type="_yz_str" indexed="true" stored="false" multiValued="false"/>
        <!-- Partition Number: Used as a filter query param -->
        <field name="_yz_pn" type="_yz_str" indexed="true" stored="false" multiValued="false"/>
        <!-- First Partition Number: The first partition in this doc's
            preflist, used for further filtering on overlapping partitions. -->
        <field name="_yz_fpn" type="_yz_str" indexed="true" stored="false" multiValued="false"/>
        <!-- If there is a sibling, use vtag to differentiate them -->
        <field name="_yz_vtag" type="_yz_str" indexed="true" stored="false" multiValued="false"/>
        <!-- Riak Key: The key of the Riak object this doc corresponds to. -->
        <field name="_yz_rk" type="_yz_str" indexed="true" stored="true" multiValued="false"/>
        <!-- Riak Bucket Type: The bucket type of the Riak object this doc corresponds to. -->
        <field name="_yz_rt" type="_yz_str" indexed="true" stored="true" multiValued="false"/>
        <!-- Riak Bucket: The bucket of the Riak object this doc corresponds to. -->
        <field name="_yz_rb" type="_yz_str" indexed="true" stored="true" multiValued="false"/>
        <!-- Flag indicating if this doc is the product of a failed object extraction -->
        <field name="_yz_err" type="_yz_str" indexed="true" stored="false" multiValued="false"/>

        <dynamicField name="*" type="ignored"  />
    </fields>

    <uniqueKey>_yz_id</uniqueKey>

    <types>
        <!-- YZ String: Used for non-analyzed fields -->
        <fieldType name="_yz_str" class="solr.StrField" sortMissingLast="true" />

        <fieldType name="string" class="solr.StrField" sortMissingLast="true" />
        <fieldType name="boolean" class="solr.BoolField" sortMissingLast="true"/>

        <fieldType name="int" class="solr.TrieIntField" precisionStep="0" positionIncrementGap="0"/>
        <fieldType name="float" class="solr.TrieFloatField" precisionStep="0" positionIncrementGap="0"/>
        <fieldType name="long" class="solr.TrieLongField" precisionStep="0" positionIncrementGap="0"/>
        <fieldType name="double" class="solr.TrieDoubleField" precisionStep="0" positionIncrementGap="0"/>

        <fieldtype name="ignored" stored="false" indexed="false" multiValued="true" class="solr.StrField" />
    </types>
</schema>
```

</details>

<details>
  <summary>Index set up commands</summary>

```bash
# Create the schema for the ssh-sessions index
curl -X PUT http://localhost:8098/search/schema/ssh-sessions -H "Content-Type: application/xml" --data-binary @ssh-sessions.xml
# Create the ssh-search index itself
curl -X PUT http://localhost:8098/search/index/ssh-sessions -H "Content-Type: application/json" -d '{"schema":"ssh-sessions"}'
# Create the bucket type
sudo riak-admin bucket-type create ssh-sessions '{"props":{"search_index":"ssh-sessions","allow_mult":true}}'
# Activate the bucket type
sudo riak-admin bucket-type activate ssh-sessions
```

</details>

<details>
  <summary>riak-search.js output (incorrect)</summary>

```json
{
  "numFound": 4,
  "maxScore": 1,
  "docs": [
    {
      "score": 1,
      "_yz_rb": "ssh-sessions",
      "_yz_rt": "ssh-sessions",
      "_yz_rk": 9,
      "_yz_id": 1,
      "hardwareId": 1,
      "state": "request-connect"
    },
    {
      "score": 1,
      "_yz_rb": "ssh-sessions",
      "_yz_rt": "ssh-sessions",
      "_yz_rk": 400000,
      "_yz_id": 1,
      "hardwareId": 2,
      "state": "connected"
    },
    {
      "score": 1,
      "_yz_rb": "ssh-sessions",
      "_yz_rt": "ssh-sessions",
      "_yz_rk": 9490,
      "_yz_id": 1,
      "hardwareId": 3,
      "state": "request-disconnect"
    },
    {
      "score": 1,
      "_yz_rb": "ssh-sessions",
      "_yz_rt": "ssh-sessions",
      "_yz_rk": 862,
      "_yz_id": 1,
      "hardwareId": 4,
      "state": "disconnected"
    }
  ]
}
```

</details>

<details>
  <summary>curl output (correct)</summary>

```json
{
  "responseHeader": {
    "status": 0,
    "QTime": 18,
    "params": {
      "shards": "192.168.1.135:8093/internal_solr/ssh-sessions",
      "q": "hardwareId:[0 TO 100]",
      "192.168.1.135:8093": "(_yz_pn:62 AND (_yz_fpn:62)) OR _yz_pn:61 OR (_yz_pn:58 AND (_yz_fpn:58)) OR _yz_pn:57 OR (_yz_pn:54 AND (_yz_fpn:54)) OR _yz_pn:53 OR (_yz_pn:50 AND (_yz_fpn:50)) OR _yz_pn:49 OR (_yz_pn:46 AND (_yz_fpn:46)) OR _yz_pn:45 OR (_yz_pn:42 AND (_yz_fpn:42)) OR _yz_pn:41 OR (_yz_pn:38 AND (_yz_fpn:38)) OR _yz_pn:37 OR (_yz_pn:34 AND (_yz_fpn:34)) OR _yz_pn:33 OR (_yz_pn:30 AND (_yz_fpn:30)) OR _yz_pn:29 OR (_yz_pn:26 AND (_yz_fpn:26)) OR _yz_pn:25 OR (_yz_pn:22 AND (_yz_fpn:22)) OR _yz_pn:21 OR (_yz_pn:18 AND (_yz_fpn:18)) OR _yz_pn:17 OR (_yz_pn:14 AND (_yz_fpn:14)) OR _yz_pn:13 OR (_yz_pn:10 AND (_yz_fpn:10)) OR _yz_pn:9 OR (_yz_pn:6 AND (_yz_fpn:6)) OR _yz_pn:5 OR (_yz_pn:2 AND (_yz_fpn:2)) OR _yz_pn:1",
      "wt": "json"
    }
  },
  "response": {
    "numFound": 4,
    "start": 0,
    "maxScore": 1,
    "docs": [
      {
        "state": "request-connect",
        "hardwareId": 1,
        "_yz_id": "1*ssh-sessions*ssh-sessions*9cdfe8d5-dd41-45f9-88bb-735c48ac3f15*41",
        "_yz_rk": "9cdfe8d5-dd41-45f9-88bb-735c48ac3f15",
        "_yz_rt": "ssh-sessions",
        "_yz_rb": "ssh-sessions"
      },
      {
        "state": "connected",
        "hardwareId": 2,
        "_yz_id": "1*ssh-sessions*ssh-sessions*4e05ed89-2a49-4f17-8885-ca79f0d292c0*41",
        "_yz_rk": "4e05ed89-2a49-4f17-8885-ca79f0d292c0",
        "_yz_rt": "ssh-sessions",
        "_yz_rb": "ssh-sessions"
      },
      {
        "state": "request-disconnect",
        "hardwareId": 3,
        "_yz_id": "1*ssh-sessions*ssh-sessions*09490ce5-6c0e-4004-ac27-1b7f361dde4e*17",
        "_yz_rk": "09490ce5-6c0e-4004-ac27-1b7f361dde4e",
        "_yz_rt": "ssh-sessions",
        "_yz_rb": "ssh-sessions"
      },
      {
        "state": "disconnected",
        "hardwareId": 4,
        "_yz_id": "1*ssh-sessions*ssh-sessions*862b4a4f-f1f4-4f39-b3f1-cc8c66ee63db*1",
        "_yz_rk": "862b4a4f-f1f4-4f39-b3f1-cc8c66ee63db",
        "_yz_rt": "ssh-sessions",
        "_yz_rb": "ssh-sessions"
      }
    ]
  }
}
```

</details>

<details>
  <summary>riak-search.js – node.js code used to search</summary>

```js
const Riak = require('basho-riak-client');

const bucketType = 'ssh-sessions';
const bucket = 'ssh-sessions';

const client = new Riak.Client(['127.0.0.1:8087'], (err, c) => {
    if (err) {
        console.log(err);
        return;
    }

    const search = new Riak.Commands.YZ.Search.Builder()
        .withIndexName('ssh-sessions')
        .withQuery('hardwareId:[0 TO 100]')
        .withCallback((err, rslt) => {
            if (err) {
                console.log(err);
                return;
            }

            console.log(rslt);
            c.stop(() => {});
        })
        .build();
    c.execute(search);
});
```

</details>

<details>
  <summary>riak-populate.js – the code I used to populate the data</summary>

```js
const Riak = require('basho-riak-client');
const async = require('async');

const data = {
    '9cdfe8d5-dd41-45f9-88bb-735c48ac3f15': {
        hardwareId: 1,
        state: 'request-connect'
    },
    '4e05ed89-2a49-4f17-8885-ca79f0d292c0': {
        hardwareId: 2,
        state: 'connected',
        host: 'host1',
        port: 22
    },
    '09490ce5-6c0e-4004-ac27-1b7f361dde4e': {
        hardwareId: 3,
        state: 'request-disconnect',
        host: 'host2',
        port: 22
    },
    '862b4a4f-f1f4-4f39-b3f1-cc8c66ee63db': {
        hardwareId: 4,
        state: 'disconnected'
    },
};

const bucketType = 'ssh-sessions';
const bucket = 'ssh-sessions';

new Riak.Client(['127.0.0.1:8087'], (err, c) => {
    if (err) {
        console.log(err);
        return;
    }

    function populateKey(key, value, callback) {
        c.fetchValue({ bucketType, bucket, key, convertToJs: true }, (err, rslt) => {
            if (rslt.isNotFound) {
                c.storeValue({ bucketType, bucket, key, value: data[key] }, (err, rslt) => {
                    if (err) {
                        return callback(err);
                    }

                    console.log(`${key} stored.`);
                    return callback(null);
                });
            }
            else {
                const riakObj = rslt.values[0];
                const value = riakObj.value;
                value.date = new Date().toISOString();
                riakObj.setValue(value);

                c.storeValue({ value: riakObj }, (err, rslt) => {
                    if (err) {
                        return callback(err);
                    }

                    console.log(`${key} updated.`);
                    return callback(null);
                });
            }
        });
    }

    async.parallel(
        Object.keys(data).map(key => {
            const value = data[key];
            return callback => populateKey(key, value, callback);
        }),
        (err, results) => {
            if (err) {
                console.log(err);
                c.stop(() => {});
                return;
            }

            c.stop(() => {});
        }
    );
});
```

</details>
