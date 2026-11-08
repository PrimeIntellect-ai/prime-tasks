Caret sign not decoded correctly in json output
When using `nsc describe account -J`, if there are some carets (wildcard) in the subject, it is not decoded correctly:

This is the normal output:
```
nsc describe account A
+--------------------------------------------------------------------------------------+
|                                   Account Details                                    |
+---------------------------+----------------------------------------------------------+
| Name                      | A                                                        |
| Account ID                | ACRGXTTH56DB2EGHMGTK6BWN5R3ZC3XZOQAXOKXW5VJJT7MS727V4Y3V |
| Issuer ID                 | OA45L5UKR3BV3LZYIKIA6SVMIUQSQ4YS2LWRG2LYQIB3CXASTRSLJSKE |
| Issued                    | 2021-01-27 17:00:31 UTC                                  |
| Expires                   |                                                          |
+---------------------------+----------------------------------------------------------+
| Max Connections           | Unlimited                                                |
| Max Leaf Node Connections | Unlimited                                                |
| Max Data                  | Unlimited                                                |
| Max Exports               | Unlimited                                                |
| Max Imports               | Unlimited                                                |
| Max Msg Payload           | Unlimited                                                |
| Max Subscriptions         | Unlimited                                                |
| Exports Allows Wildcards  | True                                                     |
| Response Permissions      | Not Set                                                  |
+---------------------------+----------------------------------------------------------+
| Jetstream                 | Disabled                                                 |
+---------------------------+----------------------------------------------------------+
| Exports                   | None                                                     |
+---------------------------+----------------------------------------------------------+

+---------------------------------------------------------------------------+
|                                  Imports                                  |
+-------+---------+--------+--------------+---------+--------------+--------+
| Name  | Type    | Remote | Local/Prefix | Expires | From Account | Public |
+-------+---------+--------+--------------+---------+--------------+--------+
| get.> | Service | get.>  | get.>        |         | B            | Yes    |
+-------+---------+--------+--------------+---------+--------------+--------+
```

This is the json output:
```
nsc describe account A -J
{
 "iat": 1611766831,
 "iss": "OA45L5UKR3BV3LZYIKIA6SVMIUQSQ4YS2LWRG2LYQIB3CXASTRSLJSKE",
 "jti": "5XUPXE52PVQANMLEXZSQWBDIAK3HD5MJIDRADHUGXSSJL7DA2OAQ",
 "name": "A",
 "nats": {
  "default_permissions": {
   "pub": {},
   "sub": {}
  },
  "imports": [
   {
    "account": "AA2OVATDKXZEYIYUV42HM2UEZX7BEDABNGK2UQKLY4UPCZ7K4FYCCB6D",
    "local_subject": "get.\u003e",
    "name": "get.\u003e",
    "subject": "get.\u003e",
    "type": "service"
   }
  ],
  "limits": {
   "conn": -1,
   "data": -1,
   "exports": -1,
   "imports": -1,
   "leaf": -1,
   "payload": -1,
   "subs": -1,
   "wildcards": true
  },
  "type": "account",
  "version": 2
 },
 "sub": "ACRGXTTH56DB2EGHMGTK6BWN5R3ZC3XZOQAXOKXW5VJJT7MS727V4Y3V"
}
```

This is a minor issue until this output is automated.

nsc version 0.0.0-dev
synadia/nats-server   nightly   efab0546062c
