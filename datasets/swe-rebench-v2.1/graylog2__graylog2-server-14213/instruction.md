IP Address search using ip slash notation shows a validation warning
<!--- Provide a general summary of the issue in the Title above -->

IP Address search using ip slash notation shows a validation warning:

> Invalid value type: Type of source_ip is ip, cannot use value 10.0.0.0/8

![image](https://user-images.githubusercontent.com/107503402/205696235-c9750298-da9a-4d5e-8c58-43150262314f.png)

## Expected Behavior
<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->

No validation warnings are shown if the search query is valid.

## Current Behavior
<!--- If describing a bug, tell us what happens instead of the expected behavior -->
<!--- If suggesting a change/improvement, explain the difference from current behavior -->

A validation warning is shown even though the query works and is valid.

## Steps to Reproduce (for bugs)
<!--- Provide a link to a live example, or an unambiguous set of steps to -->
<!--- reproduce this bug. Include code to reproduce, if relevant -->

Search using a search query that contains ip slash notation, such as: `source_ip:"10.0.0.0/8"`

## Context
<!--- How has this issue affected you? What are you trying to accomplish? -->
<!--- Providing context helps us come up with a solution that is most useful in the real world -->

Warning is confusing and incorrect.

## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->

* Graylog Version: Graylog 5.0.0
* Java Version: 17.0.5
* Elasticsearch Version: Opensearch 1.3.4
* MongoDB Version: 5.0.14
* Operating System: Ubuntun Server 20.04 LTS
* Browser version: 108.0.5359.94
