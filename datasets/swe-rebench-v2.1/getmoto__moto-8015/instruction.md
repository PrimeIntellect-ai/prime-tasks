EC2 subnet references str variable instead of [HIDDEN]
moto/ec2/models/elastic_network_interfaces.py
Under the class NetworkInterface on line 135 and 137, the code references
"subnet.vpc_id" but subnet is a str. [HIDDEN]

moto version "5.0.10.dev12"

### Additional contract requirements

- When a network interface is associated with a subnet, its VPC-related behavior must reflect the VPC associated with that subnet.
