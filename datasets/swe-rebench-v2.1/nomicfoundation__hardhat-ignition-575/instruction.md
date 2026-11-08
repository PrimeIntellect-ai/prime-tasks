rerun blocked by sent transactions message
Killing a deployment midway, then rerunning can lead to the `403` Ignition error saying you have sent transactions. Even though all the transactions where sent on the previous run by Ignition and should be tracked.

## Reproduction steps

1. Update the `examples/sample` module to deploy multiple contracts one after the other using `after`.
2. Set the node so that automining is false and the interval is long enough to kill and restart a deploy.
3. Start the first run and ctrl c after the first batch has started
4. Rerun the deployment
5. You should see the 403 error

![image](https://github.com/NomicFoundation/hardhat-ignition/assets/24030/65024f4b-70c6-4cf8-9865-d39e4588c958)
