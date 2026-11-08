secondary index query on "*_bin"  index with long string value with only digits returns nothing [JIRA: CLIENTS-502]
```
var Riak = require('basho-riak-client');
var client = new Riak.Client();
    var obj = new Riak.Commands.KV.RiakObject();
    obj.setValue({test:1});
var indexVal  ="9999999999999999";
    obj.setIndex("test_bin", [indexVal  ])
    client.storeValue({bucket:"test-bin-index", key: "test-bin-index", value: obj }, function(err, res){
        if ( err )
            return console.error(err.stack);

       client.secondaryIndexQuery({bucket: "test-bin-index", indexName: "test_bin", indexKey: indexVal  , stream: false }, function(err, res){
            if ( err )
                return console.error(err);
            console.log(res);
            process.exit(0)
        })
    });
```

result: `{ values: [], done: true, continuation: null }`

http interface works fine  via
`buckets/test-bin-index/index/test_bin/9999999999999999`


adding string prefix or suffix to index value FIX an issue
reduce number inside string by 1 fix an issue, so its works fine for `9999999999999998`
