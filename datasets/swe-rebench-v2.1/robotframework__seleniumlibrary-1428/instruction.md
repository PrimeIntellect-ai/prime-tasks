Plugins should be last thing loaded in the SeleniumLibrary __init__
In the library init, plugins are loaded after the Event Firing WebDriver. There was discussion in the slack that user wants to plugin to also add a Event Firing WebDriver class to the library. But this is not currently possible because plugins are loaded before the Event Firing WebDriver and it overwrites what plugin is doing.

To overcome this problem, add plugins as last in the SeleniumLibrary [__init__](https://github.com/robotframework/SeleniumLibrary/blob/master/src/SeleniumLibrary/__init__.py#L348).
