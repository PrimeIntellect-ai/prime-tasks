Add better support for plugin to add event firing WebDriver
For plugins, it would be easier to do something like this:
```
class MyPlugin(LibraryComponent):

    def __init__(self, ctx):
        LibraryComponent.__init__(self, ctx)
        self.event_firing_webdriver  = WhatEverYouWant
```
