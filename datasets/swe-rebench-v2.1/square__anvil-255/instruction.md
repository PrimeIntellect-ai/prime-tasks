Anvil generates AssistedInject with `create` instead of defined method name
This AssistedFactory generates differently to Dagger on Anvil 2.2.x with Dagger 2.32 or 2.34.x. (I've tried downgrading to 2.1.0 and 2.31.2 with the same issue)

Anvil defaults to just using `create` instead of reading the `@AssistedFactory` method name, in this case `build()`

```
class OrderItemChangeNotifier
@AssistedInject constructor(
    @Assisted private val activity: Activity,
    private val offlineApi: OfflineMode,
    private val orderItemChangeRelay: Relay<OrderItemChangeEvent>,
    private val featureApi: ISFeatureApi,
) {
    @AssistedFactory
    interface Factory {
        fun build(activity: Activity): OrderItemChangeNotifier
    }
}
```

```
e: build/anvil/src-gen-debug/.../OrderItemChangeNotifier_Factory_Impl.kt: (14, 8): Class 'OrderItemChangeNotifier_Factory_Impl' is not abstract and does not implement abstract member public abstract fun build(activity: Activity): OrderItemChangeNotifier defined in ....OrderItemChangeNotifier.Factory
e: build/anvil/src-gen-debug/.../OrderItemChangeNotifier_Factory_Impl.kt: (17, 10): 'create' overrides nothing
```


```
import android.app.Activity
import <our.package>.OrderItemChangeNotifier_Factory
import dagger.`internal`.InstanceFactory
import javax.inject.Provider
import kotlin.Suppress
import kotlin.jvm.JvmStatic

public class OrderItemChangeNotifier_Factory_Impl(
  private val delegateFactory: OrderItemChangeNotifier_Factory
) : OrderItemChangeNotifier.Factory {
  public override fun create(activity: Activity): OrderItemChangeNotifier =
      delegateFactory.get(activity)

  public companion object {
    @JvmStatic
    public fun create(delegateFactory: OrderItemChangeNotifier_Factory):
        Provider<OrderItemChangeNotifier.Factory> =
        InstanceFactory.create(OrderItemChangeNotifier_Factory_Impl(delegateFactory))
  }
}
```


FYI, this does compile fine if using the Dagger processor. I also tried moving the Factory to top level class, same error.
