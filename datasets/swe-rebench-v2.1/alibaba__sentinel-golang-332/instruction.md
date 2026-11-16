[BUG] estimatedQueueingDuration in ThrottlingChecker may overflow, which may cause infinite waiting
<!-- Here is for bug reports and feature requests ONLY!

If you're looking for help, please check our Dingtalk group and the Gitter room.

Please try to use English to describe your issue, or at least provide a snippet of English translation.
-->

## Issue Description

Type: *bug report*

### Describe what happened
![image](https://user-images.githubusercontent.com/13688621/100205156-b4efed80-2f3f-11eb-8c28-aa45398df9ee.png)

我加了相关的日志，发现estimatedQueueingDuration的值已经大于int64最大值了，如下
`
{"level":"info","ts":"2020-11-25 13:21:03","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":54006,"ts-ms":1606281663019,"estimatedQueueingDuration":18446744073709551461,"currentTimeNano":1606281663019051949,"interval":1000000}
{"level":"info","ts":"2020-11-25 13:42:38","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":68220,"ts-ms":1606282958743,"estimatedQueueingDuration":18446744073709551330,"currentTimeNano":1606282958743045270,"interval":1000000}
{"level":"info","ts":"2020-11-25 14:30:37","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":101379,"ts-ms":1606285837180,"estimatedQueueingDuration":18446744073709551374,"currentTimeNano":1606285837180360588,"interval":1000000}
{"level":"info","ts":"2020-11-25 14:31:10","caller":"flow/tc_throttling.go:55","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker1","pid":393,"service":"","GoID":101772,"ts-ms":1606285870585,"estimatedQueueingDuration":18446744073709551383,"currentTimeNano":1606285870585095028,"interval":1000000}
{"level":"info","ts":"2020-11-25 14:33:52","caller":"flow/tc_throttling.go:55","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker1","pid":393,"service":"","GoID":103799,"ts-ms":1606286032195,"estimatedQueueingDuration":18446744073709551149,"currentTimeNano":1606286032195488790,"interval":1000000}
{"level":"info","ts":"2020-11-25 14:42:32","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":110865,"ts-ms":1606286552392,"estimatedQueueingDuration":18446744073709551567,"currentTimeNano":1606286552392114392,"interval":1000000}
{"level":"info","ts":"2020-11-25 15:07:57","caller":"flow/tc_throttling.go:55","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker1","pid":393,"service":"","GoID":134835,"ts-ms":1606288077250,"estimatedQueueingDuration":18446744073709551463,"currentTimeNano":1606288077250908120,"interval":1000000}
{"level":"info","ts":"2020-11-25 15:12:25","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":139236,"ts-ms":1606288345973,"estimatedQueueingDuration":18446744073709551309,"currentTimeNano":1606288345973680338,"interval":1000000}
{"level":"info","ts":"2020-11-25 15:21:37","caller":"flow/tc_throttling.go:55","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker1","pid":393,"service":"","GoID":149532,"ts-ms":1606288897647,"estimatedQueueingDuration":18446744073709551198,"currentTimeNano":1606288897647921208,"interval":1000000}
{"level":"info","ts":"2020-11-25 15:35:07","caller":"flow/tc_throttling.go:63","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker2","pid":393,"service":"","GoID":166445,"ts-ms":1606289707601,"estimatedQueueingDuration":18446744073709551294,"currentTimeNano":1606289707601567729,"interval":1000000}
{"level":"info","ts":"2020-11-25 15:50:44","caller":"flow/tc_throttling.go:55","func":"flow.(*ThrottlingChecker).DoCheck","msg":"ThrottlingChecker1","pid":393,"service":"","GoID":188919,"ts-ms":1606290644177,"estimatedQueueingDuration":18446744073709551286,"currentTimeNano":1606290644177611891,"interval":1000000}
`

### Describe what you expected to happen


### How to reproduce it (as minimally and precisely as possible)

1.
2.
3.

### Tell us your environment


### Anything else we need to know?
