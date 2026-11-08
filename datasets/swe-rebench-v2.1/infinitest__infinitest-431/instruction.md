NoSuchMethodError: TestNG.addListener(ITestListener)
**Context**
 - Plugin: Infinitest for Eclipse
 - Plugin Version: 5.4.2
 - IDE: Eclipse 2024-12 (4.34.0)
- TestNG Version: 7.9.0

**Describe the bug**
I installed Infinitest into Eclipse.  It ran the unit test cases.  Most of the classes have the following error:

`NoSuchMethodError ('void org.testng.TestNG.addListener(org.testng.ITestListener)') in MyClassTest`

TestNG has addListener(ITestNGListener) and addListener(Object) but not addListener(ITestListener).  [HIDDEN]  ITestListener extends ITestNGListener.

I am guessing that Infinitest needs to handle the new (?) ITestNGListener.

**To Reproduce**

Steps to reproduce the behavior:
1. Set the project's TestNG version to 7.9.0
2. Install Infinitest into Eclipse
3. Run the unit tests
4. Open the Problems view
5. See the error described above.
