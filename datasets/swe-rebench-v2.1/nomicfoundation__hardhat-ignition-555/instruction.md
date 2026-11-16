improvement: remove the newline from deploy displays
Remove the blank line at the start of a deploy run:

![image](https://github.com/NomicFoundation/hardhat-ignition/assets/24030/51f49454-6031-4cd1-bdd0-c9f8cba46ad6)

We should match the standard expectation of a unix command line utility.

### Additional contract requirements

Status-task displays must also not begin with an extraneous blank line.
