#3133 Has been reverted
### Description

https://github.com/OpenMDAO/OpenMDAO/pull/3133 corrected some bugs related to serialization of openmdao components. In https://github.com/OpenMDAO/OpenMDAO/pull/3359, two of these changes were undone

[HIDDEN]

in ExplicitComponent and ImplicitComponent

This now leaves serialization of openmdao components broken again. Would it be possible to revisit this? My bad for not adding a unit test to check serialization. I can do this in a new PR if it's ok to re-make this change.



### Example

See https://github.com/OpenMDAO/OpenMDAO/pull/3133

### OpenMDAO Version

3.36

### Relevant environment information

_No response_
