Update from 4.13.1 to 4.16.1 lazy evaluation setups fail
Hi!

I have a few tests that didn't work anymore after update to the current version. These tests were not written by me so I can't tell you much about why they were written like that.

1. Lazy evaluation of setups
In the TestIntialize method there are 2 Setups for the same method but depending on the argument it should return another value. Initially `patternKey` and `exeKey` are both string.Empty.
```c#
            this.settingsServiceMock.Setup(x => x.GetSetting(It.Is<string>((y) => y == this.patternKey))).Returns(() => this.patternKey);
            this.settingsServiceMock.Setup(x => x.GetSetting(It.Is<string>((y) => y == this.exeKey))).Returns(() => this.exeKey);
```
In the test method however `patternKey` and `exeKey` get changed to different strings. Bevore the GetSettings method on the mock is called. Before the update a breakpoint inside the It.Is expression was hit after calling GetSettings but now it doesn't get hit anymore. I guess the evaluation of the It.is was changed so the initial value is considered. Shouldn't that be considered a breaking change? Maybe you could extend the documentation in that case. I fixed it for my case like that:

```c#
            this.settingsServiceMock.Setup(x => x.GetSetting(It.IsAny<string>())).Returns<string>(s =>
            {
                if (s == this.patternKey)
                    return this.patternKey;
                return s == this.exeKey ? this.exeKey : null;
            });
```

2. Setup generic methods with derived interfaces
The test setups a generic method twice, first with the derived interface and then with the base interface and for either setup it returns differnt object. Before the update it worked like that without issues but after the update only the setup for the base interface was used. After I changed the registration order, to first setup with the base interface and then with the derived interface, it again worked like a charm. I guessed that the setup with the base interface somehow overwrites the setup with the derived one. Is this intended?

tl;dr I was able to fix my problems, still would be nice if I could get some feedback to these issues to better understand what happens.
