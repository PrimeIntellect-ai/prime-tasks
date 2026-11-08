Introduce mock interceptor
I think it might be useful to add a **mock** interceptor programatically (similarly to https://github.com/weld/api/blob/master/weld/src/main/java/org/jboss/weld/bootstrap/event/InterceptorConfigurator.java), e.g.:

````java
WeldInitiator.from(Foo.class).addBeans(
   MockInterceptor.withBindings(FooBinding.Literal.INSTANCE).aroundInvoke((ctx, interceptedBean) -> {
                return ctx.proceed();
                })).build();
````

### Additional contract requirements

- Add a public class `org.jboss.weld.junit.MockInterceptor` that can be passed to `WeldInitiator.Builder.addBeans(...)`.
- `MockInterceptor.withBindings(Annotation... interceptorBindings)` is a public static method that returns a `MockInterceptor.Builder` pre-populated with the supplied interceptor bindings.
- `MockInterceptor.Builder` provides:
  - `beanClass(Class<?> beanClass)` returning the builder, which sets the bean class associated with the mock interceptor; when omitted, the bean class defaults to `MockInterceptor.class`.
  - `aroundInvoke(MockInterceptor.InterceptionCallback callback)` returning a `MockInterceptor` configured for `@AroundInvoke` interception.
  - `postConstruct(MockInterceptor.InterceptionCallback callback)` returning a `MockInterceptor` configured for `@PostConstruct` interception.
- `MockInterceptor.InterceptionCallback` is a functional interface with a single method `Object invoke(InvocationContext invocationContext, Bean<?> interceptedBean) throws Exception`; the intercepted bean may be `null`.
- By default, a mock interceptor is automatically enabled for the test container. A mock interceptor for which a custom bean class has been set is only enabled when that bean class is enabled via `Weld.enableInterceptors(...)`; otherwise it is not active.
