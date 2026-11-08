tljh-config set limits.cpu does not accept a float value
<!-- Thank you for contributing. These HTML comments will not render in the issue, but you can delete them once you've read them if you prefer! -->

### Bug description

Trying to set the `limits.cpu` configuration to a `float` raises a validation error.

<!-- Use this section to clearly and concisely describe the bug. -->

### How to reproduce

<!-- Use this section to describe the steps that a user would take to experience this bug. -->

`sudo tljh-config set limits.cpu 3.5`

#### Expected behaviour

<!-- Tell us what you thought would happen. -->

According to the documentation: <https://tljh.jupyter.org/en/latest/topic/tljh-config.html#tljh-set-user-limits> a float is a valid value.

#### Actual behaviour

<!-- Tell us what actually happens. -->

### Your personal set up

<!--
Tell us a little about the system you're using.
Please include information about how you installed,
e.g. are you using a distribution such as zero-to-jupyterhub or the-littlest-jupyterhub.
 -->

 - OS: Ubuntu 24.04.1 LTS
 <!-- [e.g. ubuntu 20.04, macOS 11.0] -->
 - Version(s): (The Littlest) Jupyterhub: 5.2.1, Python: 3.12.3
 <!-- e.g. jupyterhub --version, python --version --->

<details><summary>Full environment</summary>
<!-- For reproduction, it's useful to have the full environment. For example, the output of `pip freeze` or `conda list` --->

```
attrs==23.2.0
Automat==22.10.0
Babel==2.10.3
bcc==0.29.1
bcrypt==3.2.2
blinker==1.7.0
certifi==2023.11.17
chardet==5.2.0
click==8.1.6
cloud-init==24.3.1
colorama==0.4.6
command-not-found==0.3
configobj==5.0.8
constantly==23.10.4
cryptography==41.0.7
dbus-python==1.3.2
distro==1.9.0
distro-info==1.7+build1
httplib2==0.20.4
hyperlink==21.0.0
idna==3.6
incremental==22.10.0
Jinja2==3.1.2
jsonpatch==1.32
jsonpointer==2.0
jsonschema==4.10.3
launchpadlib==1.11.0
lazr.restfulclient==0.14.6
lazr.uri==1.0.6
markdown-it-py==3.0.0
MarkupSafe==2.1.5
mdurl==0.1.2
netaddr==0.8.0
netifaces==0.11.0
oauthlib==3.2.2
pexpect==4.9.0
ptyprocess==0.7.0
pyasn1==0.4.8
pyasn1-modules==0.2.8
Pygments==2.17.2
PyGObject==3.48.2
PyHamcrest==2.1.0
PyJWT==2.7.0
pyOpenSSL==23.2.0
pyparsing==3.1.1
pyrsistent==0.20.0
pyserial==3.5
python-apt==2.7.7+ubuntu3
python-debian==0.1.49+ubuntu2
python-magic==0.4.27
pytz==2024.1
PyYAML==6.0.1
requests==2.31.0
rich==13.7.1
service-identity==24.1.0
setuptools==68.1.2
six==1.16.0
sos==4.5.6
ssh-import-id==5.11
systemd-python==235
Twisted==24.3.0
typing_extensions==4.10.0
ubuntu-pro-client==8001
ufw==0.36.2
unattended-upgrades==0.1
urllib3==2.0.7
wadllib==1.3.6
wheel==0.42.0
zope.interface==6.1
```
</details>

<details><summary>Configuration</summary>
<!--
For JupyterHub, especially include information such as what Spawner and Authenticator are being used.
Be careful not to share any sensitive information.
You can paste jupyterhub_config.py below.
To exclude lots of comments and empty lines from auto-generated jupyterhub_config.py, you can do:
    grep -v '\(^#\|^[[:space:]]*$\)' jupyterhub_config.py
-->

```python
# jupyterhub_config.py
"""
JupyterHub config for the littlest jupyterhub.
"""
import os
from glob import glob
from tljh import configurer
from tljh.config import CONFIG_DIR, INSTALL_PREFIX, USER_ENV_PREFIX
from tljh.user_creating_spawner import UserCreatingSpawner
from tljh.utils import get_plugin_manager
c = get_config()  # noqa
c.JupyterHub.spawner_class = UserCreatingSpawner
c.JupyterHub.cleanup_servers = False
c.JupyterHub.hub_port = 15001
c.TraefikProxy.should_start = False
dynamic_conf_file_path = os.path.join(INSTALL_PREFIX, "state", "rules", "rules.toml")
c.TraefikFileProviderProxy.dynamic_config_file = dynamic_conf_file_path
c.JupyterHub.proxy_class = "traefik_file"
c.SystemdSpawner.extra_paths = [os.path.join(USER_ENV_PREFIX, "bin")]
c.SystemdSpawner.default_shell = "/bin/bash"
c.SystemdSpawner.unit_name_template = "jupyter-{USERNAME}"
tljh_config = configurer.load_config()
configurer.apply_config(tljh_config, c)
pm = get_plugin_manager()
pm.hook.tljh_custom_jupyterhub_config(c=c)
extra_configs = sorted(glob(os.path.join(CONFIG_DIR, "jupyterhub_config.d", "*.py")))
for ec in extra_configs:
    load_subconfig(ec)

```
</details>

<details><summary>Logs</summary>


```
Config validation error: 3.5 is not of type 'integer'.
You can still apply this change without validation by re-running your command with the --no-validate flag.
If you think this validation error is incorrect, please report it to https://github.com/jupyterhub/the-littlest-jupyterhub/issues.
```
</details>

### Additional contract requirements

- Setting `limits.cpu` to a floating-point value through `tljh-config set` must be accepted and saved as a numeric value.
- When parsing configuration values, each of the exact strings `None` and `none` must produce the null value `None`.
