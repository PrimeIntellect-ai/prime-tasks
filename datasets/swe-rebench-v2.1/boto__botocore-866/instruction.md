Paginator fix still doesn't handle all cases from before
https://github.com/boto/botocore/pull/849 requires that the starting token matches the length of the input tokens, which means all input tokens need to be specified.  While this was the case for any token that came back from a botocore response, it's not the case for customers that are handcrafting starting tokens that have semantic value.  For example, here's differing behaviors on two CLI versions:

v1.9.0

```
$ aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
    --max-items 1 --starting-token 'my.domain.name.' --debug
{
    "NextToken": "None___None___None___1",
    "ResourceRecordSets": [
        {
            "ResourceRecords": [

                {
                    "Value": "..."
                },
                {
                    "Value": "..."
                }
            ],
            "Type": "NS",
            "Name": "my.domain.name.",
            "TTL": 172800
        }
    ]
}
```

v1.10.17

```
$ aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID \
    --max-items 1 --starting-token 'my.domain.name.' --debug

Bad starting token: my.domain.name.
```

In this example, the use case is that the user wants to get information about a specific resource record set (in this case for the domain name of `my.domain.name.`).  This maps to the `StartRecordName` param name in the API.

Note: even though this is a CLI specific example, I'm filing it here because the fix for this issue will need to come from botocore.
