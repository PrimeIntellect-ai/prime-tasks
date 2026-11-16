Chrome & FF options not working in version 1.10.2
Chrome caps:
```
ChromeOptions chromeOptions = new ChromeOptions();
        chromeOptions.setCapability("enableVNC", true);
        chromeOptions.setCapability("screenResolution", 1440 + "x" + 900 + "x24");
        chromeOptions.addArguments("user-agent=" + CUSTOM_UA)
```
FF caps:
```
        FirefoxOptions firefoxOptions = new FirefoxOptions().addPreference("general.useragent.override", CUSTOM_UA);
        firefoxOptions.setCapability("enableVNC", true);
```

test (both for chrome / ff. Selenide 5.18.1):
```
WebDriverRunner.setWebDriver(new RemoteWebDriver(new URL({SELENOID_URL}), firefoxOptions / chromeOptions));
        Selenide.open("ya.ru");
        assertThat((String) Selenide.executeJavaScript("return navigator.userAgent")).isEqualTo(CUSTOM_UA);
```
for selenoid 1.10.1 this test passed, but for 1.10.2 - failed

checked with browsers, result is same
selenoid/vnc:chrome_88.0
selenoid/vnc:chrome_89.0
selenoid/vnc:firefox_86.0
selenoid/vnc:firefox:77.0

### Additional contract requirements

The browser-specific capability keys `goog:chromeOptions` (Chrome) and
`moz:firefoxOptions` (Firefox) must be preserved when a new session request is
forwarded to the browser, so that options such as the Chrome `user-agent`
argument and the Firefox `general.useragent.override` preference take effect.
The Selenoid-specific `selenoid:options` capability must not be forwarded to the
browser.
