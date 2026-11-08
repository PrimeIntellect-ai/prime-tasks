Support optional override_failsafe when doing a vacate (move_only) ES plan
## Overview
It would be great if vacate/move_only plans could optionally override_failsafe since this is the current way of bypassing validations that can/will fail if a cluster is unhealthy and/or the allocator is unhealthy.

## Possible Implementation
<!--- Not obligatory, but suggest a possible implementation, -->
<!--- or ideas how to implement this new feature. -->

## Testing
Ensure that override_failsafe: true is passed in the transient section of the plan.

## Context
Without this it's not always possible to vacate unhealthy allocators.

## Your Environment
<!--- Include as many relevant details about the environment -->
<!--- to which this new feature would be applicable (e.g., -->
<!--- run under automation, executed ad-hoc, etc.), or -->
<!--- anything else of relevance about your environment -->
<!--- (e.g., your operating system, versions you current -->
<!--- run, security requirements, etc.). -->

### Additional contract requirements

The vacate command must provide a `--override-failsafe` option so users can enable the override for a move-only Elasticsearch vacate. When enabled, the resulting transient Elasticsearch plan must include `override_failsafe: true`.
