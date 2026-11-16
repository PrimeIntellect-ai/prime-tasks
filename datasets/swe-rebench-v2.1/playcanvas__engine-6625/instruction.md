Add method for Node
Now there are 2 methods available, setPosition and setRotation, I suggest adding 1 more method setPositionAndRotation.

public setPositionAndRotation(position: Readonly<pc.Vec3>, rotation: Readonly<pc.Quat>): void;

* This will further optimize position and rotation manipulations
