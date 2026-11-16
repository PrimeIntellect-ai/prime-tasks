Portable extensions ignored -- how can I add some of them?
I'm using `org.jboss.weld:weld-junit4:1.2.1.Final` and my implementations of `javax.enterprise.inject.spi.Extension` are completely ignored.

I added the following code to my test-class to see, if the services file is actually found -- and it is:

```
    static {
        try {
            Enumeration<URL> resources = TransactionCustomerServiceTest.class.getClassLoader().getResources("META-INF/services/javax.enterprise.inject.spi.Extension");
            while (resources.hasMoreElements()) {
                URL url = resources.nextElement();
                System.out.println("********************");
                System.out.println(url);
                System.out.println(">>>>>>>>>");
                try (InputStreamReader r = new InputStreamReader(url.openStream(), StandardCharsets.UTF_8);) {
                    char[] cbuf = new char[10000];
                    while (true) {
                        int count = r.read(cbuf);
                        if (count < 0) {
                            break;
                        }
                        System.out.print(new String(cbuf, 0, count));
                    };
                }
                System.out.println("<<<<<<<<<");
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
```

I debugged through some weld-code and saw that the extensions seem to be dictated by the `WeldInitiator` -- and not discovered in the ordinary way.

I totally understand that one might not want the discovery for a junit-test. But I did not find any API to manually add the extensions which are needed for the current test. There is from(Class...), but adding the extension classes there has no effect. So how can I get my extension(s) into the junit-test?

### Additional contract requirements

- When an implementation of `javax.enterprise.inject.spi.Extension` is passed to `WeldInitiator.from(...)`, it must be registered as a portable extension of the test container, so it takes part in container startup and observes the events fired for the bean classes in that container. Supplying it there must not require any other call.
- Classes passed to `WeldInitiator.from(...)` that are not extensions must still be added to the container as bean classes, as before.
