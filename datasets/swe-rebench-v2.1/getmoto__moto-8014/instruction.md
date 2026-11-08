Autoscaling groups do not pass launch template to EC2 instances.
When creating an Auto Scaling Group using moto, the launch template argument is ignored when creating instances in the autoscaling group (only launch config is taken into account). This means that any properties of instances managed by the AutoScaling group and set in the launch template are not transferred to the instance. (In `[HIDDEN]`, we see that only the launch config is used to pass configuration to the created instances and not the launch template).

moto version: 5.0.12 installed using poetry.

### Additional contract requirements

Properties specified in the launch template associated with an Auto Scaling group must be reflected on instances launched by that group, including user data.
