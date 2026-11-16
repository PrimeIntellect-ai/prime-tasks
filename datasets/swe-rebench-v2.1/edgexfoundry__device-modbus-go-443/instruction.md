Got error "cannot transfrom protocol config Timeout value 60 to int" while sending get command
<!--🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅

Hello there! 😄

To expedite issue processing please search open and closed issues before submitting a new one.
Existing issues often contain information about workarounds, resolution, or progress updates.

Please do not remove sections of this template when submitting your issue.  If the section is not relevant to your issue, leave the section but enter "n/a" for not applicable.

Note some sections are marked "REQUIRED" and must be provided.  Never mark required sections "n/a".

🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅🔅-->


# 🐞 Bug Report

### Affected Services [**REQUIRED**]
<!-- Can you pin-point one or more EdgeX services (Data, Metadata, Command, etc...) as the source of the bug? -->
<!-- ✍️edit: --> The issue is located in: device-modbus


### Is this a regression?

<!-- Did this behavior work correctly in the previous version? -->
<!-- ✍️--> Yes

### Description and Minimal Reproduction [**REQUIRED**]
1. Deploy EdgeX by attached compose file
[docker-compose-no-secty.yml.zip](https://github.com/edgexfoundry/device-modbus-go/files/11035968/docker-compose-no-secty.yml.zip)

2. device-modbus create default profiles and devices with autoevent
3. Found error on device-modbus logs

## 🔥 Exception or Error
<pre><code>
level=ERROR ts=2023-03-22T03:22:16.766647886Z app=device-modbus source=executor.go:55 msg="AutoEvent - error occurs when reading resource HVACValues: error reading DeviceCommand HVACValues for Modbus-TCP-test-device -> cannot transfrom protocol config Timeout value 5 to int"



</code></pre>


## 🌍  Your Environment
**Deployment Environment:** Ubuntu/x86

**EdgeX Version [**REQUIRED**]:** Main


**Anything else relevant?**
