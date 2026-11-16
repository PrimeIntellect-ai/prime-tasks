Expose `unwrap` on Helidon metrics API builder types
## Environment Details
* Helidon Version: 4.x
* Helidon SE or Helidon MP
* JDK version:
* OS:
* Docker version (if applicable):

----------

## Problem Description
The Helidon neutral metrics API exposes an abstraction of metrics behavior, similar to but not identical to Micrometer's approach.

We did not intend to include every feature of Micrometer in the Helidon API but by implementing`unwrap` allow developers relatively easy access to Micrometer features (or features of other potential implementations) not included in our neutral API.

The main level types (for example `Counter` and `Timer`) have `unwrap` but the builder types _do not_ and it would be helpful if they did.
