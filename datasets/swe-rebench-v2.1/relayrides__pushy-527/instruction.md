Notifications sent while connection pool is closing may not be resolved
desc:when I close the client, I only received one response but have send ten messages.

In class ApnsChannelPool, I think these codes below has something wrong (**_please see 'added by me '  and 'modified by me'_**):

```java
class ApnsChannelPool {

    private final PooledObjectFactory<Channel> channelFactory;
    private final OrderedEventExecutor executor;
    private final int capacity;

    private final ApnsChannelPoolMetricsListener metricsListener;

    private final ChannelGroup allChannels;
    private final Queue<Channel> idleChannels = new ArrayDeque<>();

    private final Set<Future<Channel>> pendingCreateChannelFutures = new HashSet<>();
    [HIDDEN]

    private static final Logger log = LoggerFactory.getLogger(ApnsChannelPool.class);

    // added by me
    [HIDDEN]
   // added by me

    private void acquireWithinEventExecutor(final Promise<Channel> acquirePromise) {
        assert this.executor.inEventLoop();

        final Channel channelFromIdlePool = ApnsChannelPool.this.idleChannels.poll();

        if (channelFromIdlePool != null) {
            if (channelFromIdlePool.isActive()) {
                acquirePromise.trySuccess(channelFromIdlePool);
            } else {
                this.discardChannel(channelFromIdlePool);
                this.acquireWithinEventExecutor(acquirePromise);
            }
        } else {
            // We don't have any connections ready to go; create a new one if possible.
            if (this.allChannels.size() + this.pendingCreateChannelFutures.size() < this.capacity) {
                final Future<Channel> createChannelFuture = this.channelFactory.create(executor.<Channel>newPromise());
                this.pendingCreateChannelFutures.add(createChannelFuture);

                createChannelFuture.addListener(new GenericFutureListener<Future<Channel>>() {

                    @Override
                    public void operationComplete(final Future<Channel> future) throws Exception {
                        ApnsChannelPool.this.pendingCreateChannelFutures.remove(createChannelFuture);

                        if (future.isSuccess()) {
                            final Channel channel = future.getNow();

                            ApnsChannelPool.this.allChannels.add(channel);
                            ApnsChannelPool.this.metricsListener.handleConnectionAdded();

                            acquirePromise.trySuccess(channel);
                        } else {
                            ApnsChannelPool.this.metricsListener.handleConnectionCreationFailed();

                            acquirePromise.tryFailure(future.cause());

                        }
                    }
                });
            } else {
            	// modified by me
            	[HIDDEN]
            		[HIDDEN]
            	}else{
            		[HIDDEN]
            	}
               // added by me
            }
        }
    }

    public Future<Void> close() {
    	// added by me
    	[HIDDEN]
    	[HIDDEN]
    	[HIDDEN]
    		[HIDDEN]
    	}
     // added by me
        return this.allChannels.close();
    }
```

### Additional contract requirements

- When `ApnsChannelPool.close()` initiates shutdown, acquisition requests already waiting for pool capacity must complete exceptionally rather than remain unresolved.
- Any `ApnsChannelPool.acquire()` request made after the pool is closed must fail; it must not obtain a channel or remain pending.
