[2.2.0+] Cannot run waagent command inside any folder under /var/lib/waagent
Description of problem:
Cannot run any waagent command (such as: waagent -version, waagent -deprovision...) inside the any folder under /var/lib/waagent (such as: /var/lib/waagent/events)
It seems that if create a folder inside /var/lib/waagent, go into this folder, any waagent command cannot be run.

Version-Release number of selected component (if applicable):
WALinuxAgent-2.2.0+

RHEL Version:
RHEL-7.3

How reproducible:
100%

Steps to Reproduce:
1. Prepare a RHEL-7.3 VM with WALA-2.2.0+ installed.
2. Access to the /var/lib/waagent/events folder.
~]# cd /var/lib/waagent/events
4. Run waagent command
events]# waagent -version

Actual Result:
Raise exception. Cannot run this command.

events]# waagent -version
Traceback (most recent call last):
  File "/sbin/waagent", line 31, in <module>
    import azurelinuxagent.agent as agent
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/agent.py", line 29, in <module>
    import azurelinuxagent.common.event as event
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/common/event.py", line 30, in <module>
    from azurelinuxagent.common.protocol.restapi import TelemetryEventParam, \
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/common/protocol/__init__.py", line 18, in <module>
    from azurelinuxagent.common.protocol.util import get_protocol_util, \
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/common/protocol/util.py", line 30, in <module>
    from azurelinuxagent.common.osutil import get_osutil
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/common/osutil/__init__.py", line 18, in <module>
    from azurelinuxagent.common.osutil.factory import get_osutil
  File "/usr/lib/python2.7/site-packages/azurelinuxagent/common/osutil/factory.py", line 20, in <module>
    from azurelinuxagent.common.version import DISTRO_NAME, DISTRO_VERSION, \
[HIDDEN]

Expect Result:
Can run waagent command.
