"is..."-named Module properties break build
A module property with a name starting with "is" that acts as a provider breaks Dagger processing when processing the module with Anvil 2.4.0-M2. This does not happen when using straight Dagger for annotation processing. I suppose there is some problem with different beans-like name processing being applied by the processors. At a minimum, this is super-confusing; I was chasing this problem for hours before thinking of the property name and finding the actual repro path.

For example:

    @Module
    @ContributesTo(MyComponentScope::class)
    class MyModule {
        @get:Provides
        val isValidCache: BooleanArray = booleanArrayOf(false)
    }

The element needs to be injected somewhere to trigger the error:

    > Task :app:compileDebugJavaWithJavac FAILED
    MyComponent.java:86: error: cannot find symbol
    import com.example.MyModule_IsValidCacheFactory;
    ^
    symbol:   class MyModule_IsValidCacheFactory
    location: package com.example
    app/build/generated/source/kapt/debug/com/example/DaggerMyComponent.java:800: error: cannot find symbol
    return (T) new SampleViewModel(MyModule_IsValidCacheFactory.isValidCache(myComponentImpl.myModule));

If I use a different property name like 'validCache', Dagger prefixes 'get' when generating the component code: 'getValidCache()' instead of 'isValidCache()'
