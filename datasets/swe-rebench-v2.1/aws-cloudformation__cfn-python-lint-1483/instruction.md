Check whether RecordSet name is valid
*cfn-lint version: 0.28.2*

*Description of issue.*

cfn-lint could check whether the name is valid for a given hosted zone. Specifically:

```
+    "FooBarDelegation": {
+      "Type": "AWS::Route53::RecordSet",
+      "Properties": {
+        "HostedZoneName": "bar.example.com.",
+        "Name": "foo",
+        "TTL": "86400",
+        "Type": "NS",
+        "ResourceRecords": [
...
+        ]
+      }
```

could be attempted, which results in a not very clear error:

```
RRSet with DNS name foo. is not permitted in zone bar.example.com.
```

The solution is to have name `foo.bar.example.com` instead.
This came up in a highly upvoted SO question as well: https://stackoverflow.com/questions/11420063/rrset-with-dns-name-foo-is-not-permitted-in-zone-bar

It would be great if (when the values are available), cfn-lint raised an error "Name has to end with HostedZoneName"

### Additional contract requirements

- Report an error when a string `HostedZoneName` value does not end with a dot.
