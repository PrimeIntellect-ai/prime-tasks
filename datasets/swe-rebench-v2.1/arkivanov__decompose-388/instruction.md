[StackNavigation] InstanceKeeper instances of component are destroyed earlier than component itself, leading to access to released resources.
Hello. I found that in `StackNavigation` `Instance`s of component are destroyed first, and then lifecycle of component is going pause-stop-destroy. I found that when implemented pause of video play on pause of component (which IMO is good as video is not playing in background) and also "releasing" (i.e. destroying with release of resources like threads etc) ExoPlayer in `onDestroy` method of `Instance`.

So, when I navigate back from screen with video I see this warning in logs:

```
Handler (android.os.Handler) {c3b8656} sending message to a Handler on a dead thread
java.lang.IllegalStateException: Handler (android.os.Handler) {c3b8656} sending message to a Handler on a dead thread
```

That is a clear signal that Instance::onDestroy is called first, and then Lifecycle.Callbacks::onPause is called (because stack trace leads to onPause).

I also found the source of this exception in Decompose code. [HIDDEN] I think reproductions steps are not needed as the error is clear from code below:

[HIDDEN]

Why this should not happen: because instances of classes should be destroyed only when there are no external links to them, i.e. noone can access already destroyed classes or releases resources. On android, ViewModel is destroyed later than Activity, for example.

Btw, I use 2.0.0-alpha-01 version, and tried with 2.0.0-alpha-02 - the error is still here. Artifacts used: `decompose` and `extensions-compose-jetpack` on Android 13 (Pixel Experience).

### Additional contract requirements

- When a child component is removed or marked `DESTROYED`, its lifecycle must be destroyed before its `InstanceKeeper` instances are destroyed.
