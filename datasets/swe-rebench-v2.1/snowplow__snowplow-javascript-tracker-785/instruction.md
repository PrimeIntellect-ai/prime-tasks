Handle errors in tracker callback
If errors occur in the tracker callback method e.g:
```
            window.snowplow(function() {
                var sp = this.sp;
                sp.thisWillError(); //Function doesn't exist
            });
```

This will prevent the tracker from continuing to process the event queue. Whilst this is an unlikely scenario, it can exhibit itself when multiple versions of the tracker are loaded on the same page. This results in a race condition (#560) where either version of the tracker can run the callback function (and may not have the desired function on the tracker).

Ideally, we wouldn't see two incompatible versions of sp.js loaded on the same page but as this can happen (and has happened) then we should at least handle these errors so the tracker can continue to process events.
