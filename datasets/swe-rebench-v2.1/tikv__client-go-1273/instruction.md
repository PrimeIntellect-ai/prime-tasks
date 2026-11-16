1 tikv down may affect too long time when enable forwarding
Related Issue: https://github.com/pingcap/tidb/issues/52394

### Unexpected

Issue description: 1 tikv down will cause qps drop and did not recover for a long time, which is unexpected.

Related metrics:

TiDB:

The problem is, when 1 tikv down, TiDB doesn't invalidate the regions in the store and get region from PD, and then still use forwarding feature to send request.

<img width="1456" alt="image" src="https://github.com/tikv/client-go/assets/26020263/1977aff4-3864-4513-89b0-6a80028e0218">



TiKV:

<img width="1456" alt="image" src="https://github.com/tikv/client-go/assets/26020263/822c4e61-bfd6-454b-862c-934a7f532f42">


### Expected

The expected TiDB metrics maybe like following, when 1 tikv server down, TiDB needs to invalidate the regions in the store and get region from PD, since those regions will has new leader.

<img width="1463" alt="image" src="https://github.com/tikv/client-go/assets/26020263/f2f8f842-5378-4a71-b86d-32525237b943">
