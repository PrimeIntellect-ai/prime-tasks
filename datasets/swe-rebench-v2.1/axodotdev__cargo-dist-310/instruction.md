Copyright and license notice on the generated CI config
My projects follow <https://reuse.software> so I ensure that there is copyright and license info for each file in my repo. As far as I can tell, the generated CI file is just a part of this crate so it's probably "MIT or Apache-2.0". However, it's not clear what the copyright statement should be.

It would be great if this package was REUSE compliant, but I'd be happy with just a correct notice on the generated CI script.

### Additional contract requirements

The generated CI script must begin with a copyright and license notice. The notice must consist of exactly the following lines, in this order, at the very start of the generated CI script:

# Copyright 2022-2023, axodotdev
# SPDX-License-Identifier: MIT or Apache-2.0
#
