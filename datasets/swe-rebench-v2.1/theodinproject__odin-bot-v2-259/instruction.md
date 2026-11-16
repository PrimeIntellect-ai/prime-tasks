Bug: Point grants should be throttled to only one per user per message.
<!-- Thank you for taking the time to submit a bug report to The Odin Project. In order to get issues closed in a reasonable amount of time, you must include a baseline of information about the bug in question. Please read this template in its entirety before filling it out to ensure that it is filled out correctly. -->

Complete the following REQUIRED checkboxes:
-   [x] I have thoroughly read and understand [The Odin Project Contributing Guide](https://github.com/TheOdinProject/theodinproject/blob/main/CONTRIBUTING.md)
-   [x] The title of this issue follows the `Bug - location of bug: brief description of bug` format, e.g. `Bug - points command: Extra whitespace causes command to not be called`

The following checkbox is OPTIONAL:
<!-- Completing this checkbox does not guarantee you will be assigned this issue, but rather lets us know you are interested in working on it. -->
-   [x] I would like to be assigned this issue to work on it

<hr>

**1. Description of the Bug:**
<!-- A clear and concise description of what the bug is. Include any screenshots that may help show the bug in action. -->
When a user sends a message with multiple users in it, each user should only be granted 1 point.

* `@user1 ++ @user1 ++` should only grant user1 a single point.
* `@user1 ++ @user2 ++` should grant each user a single point.


**2. How To Reproduce:**
<!--
What steps one might need to take in order to reproduce this bug, e.g.:
1. Log in
2. Visit a lesson page
3. Click the complete button
4. The complete button does not update
-->
Send a message granting a user more than 1 point.


**3. Expected Behavior:**
<!--
A brief description of what you expected to happen, e.g.:
1. Log in
2. Visit a lesson page
3. Click the complete button
4. The complete button updates correctly
 -->

User should only be granted 1 point, regardless of the number of `++`'s.


**4. Desktop/Device:**
<!-- The more information you are able to provide, the better. -->
-   Device: <!-- [e.g. iPhone6] -->
-   OS: <!-- [e.g. iOS] -->
-   Browser: <!-- [e.g. chrome, safari] -->
-   Version: <!-- [e.g. 22] -->

**5. Additional Information:**
<!-- Any additional information about the bug. -->

![image](https://user-images.githubusercontent.com/36272822/212191488-5a4f20dc-0dc4-4309-a1be-985533a50489.png)

### Additional contract requirements

- For each occurrence of a user after their first `++` mention in the same message, also send `Only maintainers or core members can give double points!`.
- Send the `Only maintainers or core members can give double points!` warning(s) before the point-grant confirmation(s) for that message.
