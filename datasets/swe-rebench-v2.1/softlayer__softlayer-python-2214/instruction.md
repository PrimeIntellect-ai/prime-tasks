Errors with order place
```
$>  slcli order place --verify --billing monthly SINGLE_E3_1270_V6_CL FRANKFURT02 DISK_CONTROLLER_NONRAID BANDWIDTH_0_GB 1_GBPS_PRIVATE_NETWORK_UPLINK REBOOT_KVM_OVER_IP 1_IP_ADDRESS UNLIMITED_SSL_VPN_USERS_1_PPTP_VPN_USER_PER_ACCOUNT OS_UBUNTU_20_04_LTS_FOCAL_FOSSA_64_BIT INTEL_INTEL_XEON_3_80 RAM_16_GB_DDR4_2666_ECC_NON_REG HARD_DRIVE_1_00_TB_SATA_2 AUTOMATED_NOTIFICATION NESSUS_VULNERABILITY_ASSESSMENT_REPORTING MONITORING_HOST_PING  NOTIFICATION_EMAIL_AND_TICKET  --complex-type SoftLayer_Container_Product_Order_Hardware_Server
An unexpected error has occured:
Traceback (most recent call last):
  File "C:\Users\allmi\Code\py311\Lib\site-packages\SoftLayer\CLI\core.py", line 182, in main
    cli.main(**kwargs)
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 1055, in main
    rv = self.invoke(ctx)
         ^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 1657, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 1657, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 1404, in invoke
    return ctx.invoke(self.callback, **ctx.params)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 760, in invoke
    return __callback(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\decorators.py", line 84, in new_func
    return ctx.invoke(f, obj, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\click\core.py", line 760, in invoke
    return __callback(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\allmi\Code\py311\Lib\site-packages\SoftLayer\CLI\order\place.py", line 68, in cli
    [HIDDEN]
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
TypeError: 'in <string>' requires string as left operand, not NoneType

Feel free to report this error as it is likely a bug:
    https://github.com/softlayer/softlayer-python/issues
The following snippet should be able to reproduce the error
```

### Additional contract requirements

- When `order place` is invoked without a complex type and the datacenter lookup returns no datacenters, it must raise a `SoftLayerError` with the exact message `A complex type must be specified with the order`.
- When the datacenter lookup yields no matching datacenter, `order place` must handle the missing match without raising the reported `TypeError`.
