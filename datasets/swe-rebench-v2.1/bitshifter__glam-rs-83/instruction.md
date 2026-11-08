impl Add<Quat> and Sub<Quat> for Quat
In short: Through a somewhat complicated chain of traits and supertraits in multiple different libraries, I've found myself needing glam::Quat to implement addition and subtraction. I've started working on a PR.

In long: I'm trying to implement skeletal animation for the bevy engine. They use glam, and rotations are represented by your quaternions. We're looking to use the splines crate to handle interpolation between keyframes, which is a very generic crate. It does however require the supplied type to implement addition and subtraction, and through a shim I've managed to get it working, but at the cost of user convenience. The splines crate provides implementations of its traits for a number of external math crates, but I am unable to add support for glam because of the requirement of these ops.

I understand that adding support for addition and subtraction ops might mislead users who are trying to combine rotations, but perhaps with good documentation we can mitigate this risk and steer them towards correct usage.
