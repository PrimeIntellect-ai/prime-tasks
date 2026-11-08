PR2 submechanism for one arm only
The [PR2 URDF](https://gist.github.com/dhruvms/513484f143f949c99c77f05551b2ba49) that I am using has a 45-dimensional joint configuration vector. For my application, I only care about 7 of those joints in the right arm. The first of those (_r_shoulder_pan_joint_) joins _torso_lift_link_ and _r_shoulder_pan_link_, but _torso_lift_link_ has three other child branches that I do not care about. I have tried:
1. Using `submechanism`
    - Rooting it at _torso_lift_link_ brings the three child branches that I do not care about into the mechanism.
    - Rooting it at _r_shoulder_pan_link_ means I lose _r_shoulder_pan_joint_ in my mechanism.
2. Using `remove_joint!`
    - For this URDF at least, any call that I have tried to make to `remove_joint!` gives me a _"Graph is not connected."_ error.

Is there a way to work with a partial chain from a URDF?

### Additional contract requirements

Provide `remove_subtree!(mechanism, body)` so a user can prune an unwanted child branch from a URDF mechanism without disconnecting the remaining mechanism. Removing an unwanted branch removes its bodies and incident joints; leaving the desired branch in place must retain the joint connecting that branch to its parent.
