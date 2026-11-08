Add a lifecycle event for server stop failed
**Describe the feature**
Add a lifecycle event for server stop failed.

**Additional context**
Based on the [documentation](https://javalin.io/documentation#lifecycle-events), the `serverSt*` lifecycle events are presumably designed to mirror [Jetty's lifecycle events](https://github.com/eclipse/jetty.project/blob/jetty-10.0.x/jetty-util/src/main/java/org/eclipse/jetty/util/component/LifeCycle.java). Either way, the difference is that Javalin wisely separated failed into start failed. However, stop can fail too. It makes sense to have both events. Is it intentional to not have a stop failed event?

Furthermore, it would be nice to obtain the exception that caused the `serverStartFailed` and `serverStopFailed` events. What do you think about adding a new `ExceptionalEventHandler` that the failure events use? A downside is that this will become baked into the API and in the future a failed start or failed stop may not be initiated by an exception. This might also require a breaking change.

I'm happy to provide a PR if you think this is a good idea.

Thanks.
