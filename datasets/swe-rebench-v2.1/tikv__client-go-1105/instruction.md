`PreferLeader` doesn't try followers
It seems `PreferLeader` is broken after https://github.com/tikv/client-go/pull/843. In the following case, followers won't be tried even when they are available.

```go
func (s *testRegionRequestToThreeStoresSuite) TestDebugPreferLeader() {
	key := []byte("key")
	bo := retry.NewBackoffer(context.Background(), -1)

	// load region into cache
	loc, err := s.cache.LocateKey(bo, key)
	s.Require().NoError(err)

	// make leader unreachable
	region := s.cache.GetCachedRegionWithRLock(loc.Region)
	leader, _, _, _ := region.WorkStorePeer(region.getStore())
	atomic.StoreUint32(&leader.livenessState, uint32(unreachable))

	// make request
	req := tikvrpc.NewReplicaReadRequest(tikvrpc.CmdGet, &kvrpcpb.GetRequest{Key: key}, kv.ReplicaReadPreferLeader, nil)
	req.ReadReplicaScope = oracle.GlobalTxnScope
	req.TxnScope = oracle.GlobalTxnScope

	// setup mock client
	s.regionRequestSender.client = &fnClient{fn: func(ctx context.Context, addr string, req *tikvrpc.Request, timeout time.Duration) (response *tikvrpc.Response, err error) {
		logutil.BgLogger().Sugar().Infof(">>> rpc to %s", addr)
		return &tikvrpc.Response{Resp: &kvrpcpb.GetResponse{Value: []byte(addr)}}, nil
	}}

	logutil.BgLogger().Sugar().Info(s.regionRequestSender.SendReqCtx(bo, req, loc.Region, time.Second, tikvrpc.TiKV))
}
```

![2023-12-28_132554](https://github.com/tikv/client-go/assets/6850317/db912e24-10dd-44a0-8095-26f44d2b5ab8)

### Additional contract requirements

- When the leader and all followers are unreachable, the request must return no Go error and a region error recognized by `IsFakeRegionError`.
