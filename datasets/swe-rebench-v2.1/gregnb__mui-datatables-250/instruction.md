[Bug][Per page] Page is greater than the total available
<!--- Provide a general summary of the issue in the Title above -->
There is an exception, when I try to change "per page" option in the MUITable at the last page (data length equals to 29, and we change per page from 10 items to 15 items, and expect total 2 pages, but got the exception: ```Provided options.page of `2` is greater than the total available page length of `1` ```)
Btw, if data length equals to 30, there are no exceptions in this case.

Such problem already have been solved at #48, but seems not at all.

<!--
    Thank you very much for contributing to MUI-datatables by creating an issue! ❤️
-->

## Expected Behavior
<!---
    If you're describing a bug, tell us what should happen.
    If you're suggesting a change/improvement, tell us how it should work.
-->
We don't have an exception, and can see 2 pages with our data

## Current Behavior
<!---
    If describing a bug, tell us what happens instead of the expected behavior.
    If suggesting a change/improvement, explain the difference from current behavior.
-->
We have exception on display ```Provided options.page of `2` is greater than the total available page length of `1` ```

## Steps to Reproduce (for bugs)
<!---
    Provide a link to a live example (you can use codesandbox.io) and an unambiguous set of steps to reproduce this bug.
    Include code to reproduce, if relevant (which it most likely is).
-->
Live example: https://codesandbox.io/s/6vlml849zk

1. Go to last page (page number 3)
2. Change option "per page" from "10" to "15"
3. Boom!

## Your Environment
<!--- Include as many relevant details about the environment with which you experienced the bug. -->

| Tech         | Version |
|--------------|---------|
| Material-UI  |    1.4.0     |
| MUI-datatables  |     ^2.0.0-beta-32    |
| React        |    16.5.0     |
| browser      |    Chrome     |
