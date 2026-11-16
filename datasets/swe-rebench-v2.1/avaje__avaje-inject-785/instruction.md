Usage of @RequiresProperty on interface with different implementations
Is it possible to use @RequiresProperty to create beans of same interface in a factory?
I'm using avaje 11.3

I'm trying something like:

```java
@Factory
class MyServiceFactory {

    @Bean
    @RequiresProperty(value = "service.type", equalTo = "one")
    MyService myServiceOne() {
        return new MyServiceOne();
    }

    @Bean
    @RequiresProperty(value = "service.type", equalTo = "two")
    MyService myServiceTwo() {
        return new MyServiceTwo();
    }
}
```

But I see in the generated code that only the 2nd bean creation will be ever called making instanciation of bean with property `service.type=one` never happening.

Generated module code:
```java
@Override
  public void build(Builder builder) {
    // create beans in order based on constructor dependencies
    // i.e. "provides" followed by "dependsOn"
    build_example_MyServiceFactory(builder);
    build_example_MyService(builder);
    build_example_MyApp(builder);
  }

  @DependencyMeta(type = "example.MyServiceFactory")
  private void build_example_MyServiceFactory(Builder builder) {
    MyServiceFactory$DI.build(builder);
  }

  @DependencyMeta(
      type = "example.MyService",
      method = "example.MyServiceFactory$DI.build_myServiceTwo",
      dependsOn = {"example.MyServiceFactory"},
      autoProvides = {"example.MyService"})
  private void build_example_MyService(Builder builder) {
    MyServiceFactory$DI.build_myServiceTwo(builder);
  }

  @DependencyMeta(
      type = "example.MyApp",
      dependsOn = {"example.MyService"})
  private void build_example_MyApp(Builder builder) {
    MyApp$DI.build(builder);
  }
```

stack trace when running with service.type=one
```
Exception in thread "main" java.lang.IllegalStateException: Injecting null for example.MyService name:!myService when creating class example.MyApp - potential beans to inject: []. Check for missing module? [ missing beanScopeBuilder.modules() ]. If it is expected to be externally provided, missing beanScopeBuilder.bean() ?
	at io.avaje.inject.spi.DBuilder.getBean(DBuilder.java:386)
	at io.avaje.inject.spi.DBuilder.get(DBuilder.java:333)
	at example.MyApp$DI.build(MyApp$DI.java:11)
	at example.ExampleModule.build_example_MyApp(ExampleModule.java:78)
	at example.ExampleModule.build(ExampleModule.java:57)
	at io.avaje.inject.DBeanScopeBuilder.build(DBeanScopeBuilder.java:272)
	at example.MyApp.main(MyApp.java:21)
```
