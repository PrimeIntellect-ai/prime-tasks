The complex step mode never gets set on the SubModel comp.
### Description

To complex step across a SubModel, openmdao needs to [HIDDEN] at some point, so that the SubModel can set the mode on its problem. However, [HIDDEN]

### Example

Given an example from UQ.

### OpenMDAO Version

3.28-1.dev

### Relevant environment information

_No response_

### Additional contract requirements

- Complex-step total derivatives must work across a SubModel, including when it is nested inside another system. The resulting derivatives must account for the computation performed by the SubModel's contained problem.
