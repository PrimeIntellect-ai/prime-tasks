Driver events
I discovered this : http://www.abodeqa.com/2014/06/08/event-listeners-in-selenium-webdriver/

It would be great to get this included inside FluentLenium.

### Additional contract requirements

FluentLenium exposes the Selenium `EventFiringWebDriver` event listeners through an events API.

`Fluent.events()` in `org.fluentlenium.core.Fluent` returns an `org.fluentlenium.core.events.EventsRegistry`. It throws `IllegalStateException` when the underlying driver is not an `org.openqa.selenium.support.events.EventFiringWebDriver`.

Every registration method on `EventsRegistry` returns the same `EventsRegistry` instance, so registrations can be chained.

The listener interfaces live in `org.fluentlenium.core.events`:

- `ElementListener` declares `void on(FluentWebElement element, WebDriver driver)`. It is registered with `beforeClickOn`, `afterClickOn`, `beforeChangeValueOf` and `afterChangeValueOf`.
- `FindByListener` declares `void on(By by, FluentWebElement element, WebDriver driver)`. It is registered with `beforeFindBy` and `afterFindBy`.
- `NavigateAllListener` declares `void on(String url, WebDriver driver, NavigateAllListener.Direction direction)` and an enum `Direction` with the values `BACK` and `FORWARD`. It is registered with `beforeNavigate` and `afterNavigate`.
- `NavigateToListener` declares `void on(String url, WebDriver driver)`. It is registered with `beforeNavigateTo` and `afterNavigateTo`.
- `NavigateListener` declares `void on(WebDriver driver)`. It is registered with `beforeNavigateBack`, `afterNavigateBack`, `beforeNavigateForward` and `afterNavigateForward`.
- `ScriptListener` declares `void on(String script, WebDriver driver)`. It is registered with `beforeScript` and `afterScript`.
- `ExceptionListener` declares `void on(Throwable throwable, WebDriver driver)`. It is registered with `onException`.

The registered listeners observe the following behaviour:

- `beforeClickOn` and `afterClickOn` listeners run before and after each element click performed through the event-firing driver.
- `beforeFindBy` and `afterFindBy` listeners run around every `By`-based lookup, whether it is started from the driver or from an element. The listener receives the `By`, the element for element-scoped lookups (or null for driver-scoped lookups) and the driver.
- The generic navigation listeners registered with `beforeNavigate` and `afterNavigate` run before and after direct URL navigation, back navigation and forward navigation. For direct URL navigation the target URL is provided; for back and forward navigation the direction is `BACK` and `FORWARD` respectively.
- `beforeNavigateTo` and `afterNavigateTo` listeners run for direct URL navigation with the target URL.
- `beforeNavigateBack` and `afterNavigateBack` listeners run for back navigation; `beforeNavigateForward` and `afterNavigateForward` listeners run for forward navigation.
- `beforeChangeValueOf` and `afterChangeValueOf` listeners run around element value changes.
- `beforeScript` and `afterScript` listeners run around JavaScript execution through the driver.
- `onException` listeners run when the event-firing driver reports an exception raised by an element operation.
