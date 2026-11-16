Payment is stuck in flight after no routes are found
### Background

Two days ago, two payment attemps to Pheonix got stuck `IN_FLIGHT` and they still are now. Both attempts have the same output in ours logs:

```
May 22 21:01:48 ip-10-2-1-20 lnd[2438]: 2020-05-22 21:01:48.077 [WRN] CRTR: Failed to find route for payment 5eb9b3641ddb5395df448a19e6c647086a3d6c97715fdea48c363c41b26afcee: missing feature dependency: 9
May 22 21:01:48 ip-10-2-1-20 lnd[2438]: 2020-05-22 21:01:48.077 [ERR] CRTR: Payment with hash 5eb9b3641ddb5395df448a19e6c647086a3d6c97715fdea48c363c41b26afcee failed: missing feature dependency: 9
```

One of the invoices is `lnbc10n1p0vs0d2pp5t6umxeqamdfeth6y3gv7d3j8pp4r6myhw90aafyvxc7yrvn2lnhqdqc2p5x7etwd9uzqurp09kk2mn5xqrrss9qtzqqqqqq9qqqsp5fkhdnf2gl92xrfw80as34refnsm9a57rzmq38tm7ysvwpchkhussrzjqwryaup9lh50kkranzgcdnn2fgvx390wgj5jd07rwr3vxeje0glcll7vvhf9q6ppwqqqqqlgqqqqqeqqjq08rlj7aup45w2pwz7pay2ct9fs933vt8ck5ex3zerfgatar2ql0kzrw0nmlyn95hvtz0g20ah8649xzvsene6we02x8arrg862mwv5qpuaar3w`

The output of track payment is:
```
$ lncli trackpayment 5eb9b3641ddb5395df448a19e6c647086a3d6c97715fdea48c363c41b26afcee
+------------+--------------+--------------+--------------+-----+----------+----------+-------+
| HTLC_STATE | ATTEMPT_TIME | RESOLVE_TIME | RECEIVER_AMT | FEE | TIMELOCK | CHAN_OUT | ROUTE |
+------------+--------------+--------------+--------------+-----+----------+----------+-------+
+------------+--------------+--------------+--------------+-----+----------+----------+-------+
Amount + fee:   0 + 0 sat
Payment hash:   5eb9b3641ddb5395df448a19e6c647086a3d6c97715fdea48c363c41b26afcee
Payment status: IN_FLIGHT
```

### Your environment

* `lncli version 0.10.0-beta commit=v0.10.0-beta`
* `Linux ip-10-2-1-20 5.3.0-1017-aws #18~18.04.1-Ubuntu SMP Wed Apr 8 15:12:16 UTC 2020 x86_64 x86_64 x86_64 GNU/Linux`
* `Bitcoin Core Daemon version v0.18.1`

### Steps to reproduce

Generate an invoice with Pheonix app and try to pay it. This seems to be happening consistentely.

### Expected behaviour

Either the payment should be succesfull or it should correctly fail the attempt.

### Actual behaviour

The payment is stuck `IN_FLIGHT` for days.
