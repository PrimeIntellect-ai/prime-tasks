With "delete_aliases: True" but no aliases present, "close" doesn't close
I love the "delete_aliases" flag in curator 4.
However, people should be aware that closing the indexes will fail if `delete_aliases` is set to `true` and there is no alias to delete. This is due to elasticsearch's behaviour:
`curl -XDELETE host:port/some_index/_alias/_all`
throws an error when there was no alias associated with the `some_index`. It looks like "all" means "one to many" here. I expected a "zero to many" interpretation and was surprised.
This error will cause the `close`  operation to fail.
(This remains true if `continue_if_exception: False` is set, because this will not force the current action to be continued, but the subsequent actions, as explained in https://www.elastic.co/guide/en/elasticsearch/client/curator/4.0/option_continue.html)
