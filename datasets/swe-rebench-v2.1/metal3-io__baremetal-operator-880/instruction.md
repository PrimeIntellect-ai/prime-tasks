baremetal IPI power_interface for irmc miss IPMI credentials
When we deployed bare metal using IPI, we encountered the following errors:
```
| last_error             | Failed to validate power driver interface for node e88070b5-afe2-4132-b697-93ee2bf10c1b. Error: Missing the following IPMI credentials in node's driver_info: ['ipmi_address']
```
Check that there is no ipmi related information in driver_info
```
| driver_info            | {​​​​​​​'deploy_kernel': 'http://192.168.20.2:80/images/ironic-python-agent.kernel', 'deploy_ramdisk': 'http://192.168.20.2:80/images/ironic-python-agent.initramfs', 'irmc_address': '192.168.30.25', 'irmc_password': '******', 'irmc_username': 'admin'}​​​​​​​ |
```
But in our previous use, there will be ipmi information in driver_info.

I think it may be related to this PR. https://github.com/metal3-io/baremetal-operator/pull/848

### Additional contract requirements

For iRMC access, the driver information must include `ipmi_address` matching the BMC hostname and must provide the configured BMC username and password as `ipmi_username` and `ipmi_password`, respectively.
