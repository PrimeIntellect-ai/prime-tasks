Strategy check return only the first enabled
### Describe the bug

In the [commit https://github.com/Unleash/unleash-client-java/commit/78a0d33358bb375d6abe8d08de60f704a12961a6](feat: strategy variants) has been introduced a bug.
When retrieving the toggle enabled strategies it is returned only the first. In case of multiple strategy the the toggle will result disabled even when the context is valid.

See into class `src/main/java/io/getunleash/DefaultUnleash.java`
```
        } else {
            enabledStrategy =
                    featureToggle.getStrategies().stream()
                            .filter(
                                    strategy -> {
                                        Strategy configuredStrategy =
                                                getStrategy(strategy.getName());
	@@ -181,13 +184,33 @@ private boolean checkEnabled(
                                        }

                                        return configuredStrategy.isEnabled(
                                                strategy.getParameters(), context);
                                    })
                            [HIDDEN]
```

### Steps to reproduce the bug

1. Create a toggle with more then one strategy
2. Check if the toggle is enabled having as context valued that meet second or further strategy in the list.
3. Should expect to return enabled true but is false

### Expected behavior

When calling the method `isEnabled` with context that meet one of the strategy should expect `true` as response

### Logs, error output, etc.

_No response_

### Screenshots

_No response_

### Additional context

_No response_

### Unleash version

8.3.0 ( introduced in this commit-78a0d33358bb375d6abe8d08de60f704a12961a6)

### Subscription type

Enterprise

### Hosting type

Hosted by Unleash

### SDK information (language and version)

java
