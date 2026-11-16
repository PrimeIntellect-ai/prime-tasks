AUTO_RESOLVE_TITLES=false ignored when validating URLs during creation
<!--
Before opening an issue, just take into account that this is a completely free of charge and open source project.
I'm always happy to help and provide support, but some understanding will be expected.
I do this in my own free time, so expect some delays when implementing new features and fixing bugs, and don't take it personal if an issue gets eventually closed.
You may also be asked to provide tests or ways to reproduce reported bugs.
Try to be polite, and understand it is impossible for an OSS project to cover all use cases.

With that said, please fill in the information requested next. More information might be requested next (like logs or system configs).
-->

#### How Shlink is set-up

* Shlink Version: 3.0.0
* PHP Version: 8.1.2
* How do you serve Shlink: Self-hosted nginx
* Database engine used: PostgreSQL

#### Summary

<!-- Provide a summary describing the problem you are experiencing. -->

I have `AUTO_RESOLVE_TITLES` set to false and now the instance is resolving the title for me anyway.

#### Current behavior

<!-- How is it actually behaving (and it shouldn't)? -->

It is automatically resolving the titles

#### Expected behavior

<!-- How did you expected to behave? -->

It should not resolve the title.

#### How to reproduce

<!-- Provide steps to reproduce the bug. -->

Create a new shortlink with `shlink-php-sdk`.

### Additional contract requirements

When `AUTO_RESOLVE_TITLES` is false, creating a shortlink must not automatically resolve or populate its title, even when URL validation is requested.
