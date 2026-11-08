WeldJunit5Extension + @Nested test strange behavior
```
@ExtendWith(WeldJunit5Extension.class)
class MyTest {
	@WeldSetup
	WeldInitiator weld = WeldInitiator.of(MyBean.class);
	@Inject
	MyBean myBean;

	@BeforeEach
	void setup() {
		myBean.mySetup();
	}

	@Nested
	class MyNestedTest {
		@WeldSetup
		WeldInitiator weld = WeldInitiator.of(MyBean.class);

		@Test
		void test() {
			assertNotNull(myBean);
		}
	}
}
```

With org.jboss.weld:weld-junit5:1.3.1.Final it's all green, the test passes.
Since org.jboss.weld:weld-junit5:2.0.0.Final it ends up with `NPE` in `setup()` instead.

I've created sample projects using weld-junit5 and spring-test for comparison. The spring analogue of test passes without any problems (below).

```
@SpringJUnitConfig(MyConfiguration.class)
class MyTest {
	@Inject
	MyBean myBean;

	@BeforeEach
	void setup() {
		myBean.mySetup();
	}

	@Nested
	@SpringJUnitConfig(MyConfiguration.class)
	class MyNestedTest {
		@Test
		void test() {
			assertNotNull(myBean);
		}
	}
}
```

[spring-test-nested-test.zip](https://github.com/weld/weld-junit/files/3739538/spring-test-nested-test.zip)
[weld-junit5-nested-test.zip](https://github.com/weld/weld-junit/files/3739539/weld-junit5-nested-test.zip)

Once again: I'm not sure if it is a regression or I should never use `WeldInitiator` in such way, but please, take a look.

### Additional contract requirements

- When a nested test runs in the shown outer-and-nested `WeldInitiator` setup, the enclosing test instance's `@Inject MyBean` must be available to its `@BeforeEach` method and accessible from the nested test.
