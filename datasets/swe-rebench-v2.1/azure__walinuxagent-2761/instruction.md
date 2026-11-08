WALinuxAgent doesn't download all .crt and .prv files from KeyVault
Not sure if this is a bug but I will try to explain as much as I can.

Environment: Virtual Machine Scale Set - Azure (West EU, West US, Japan, Asia,.. all regions impacted)

We are doing deployments of VMSS in azure using ARM template and ansible playbook with some configurations.
Before running the ansible, we are using the following to push certficates from KV:

TEMPLATE
{
    "type": "Microsoft.Compute/virtualMachines",
    "name": "Region1VM",
    ...
    "properties": {
    ...
    "osProfile": {
            "computerName": "Region1VM",
    ...
    "secrets": [
                {
                    "sourceVault": {
                        "id": "[resourceId('Microsoft.KeyVault/vaults', Region1KeyVault)]"
                    },
                    "vaultCertificates": [
                        {
                            "certificateUrl": "[reference(resourceId('Microsoft.KeyVault/vaults/secrets', 'Region1KeyVault', 'SampleCertificateAsSecret')).secretUriWithVersion]",
                            "certificateStore": "My"
                        }
                    ]
                }
            ],
        },
    ...
    }
}

CODE
![image](https://user-images.githubusercontent.com/124268307/216367634-fdc263b6-0e5f-4cd3-9a75-6233dc72fc37.png)

LINK
https://devblogs.microsoft.com/premier-developer/centralized-vm-certificate-deployment-across-multiple-regions-with-arm-templates/#part-2-push-certificate-from-the-regional-key-vault-to-the-virtual-machine

after running this part of the ARM template we do some certificate copies from var/lib/waagent to another location but it fails with the below error:

"could not find or access '/var/lib/waagent/nameexample.prv"

![image](https://user-images.githubusercontent.com/124268307/216368423-265403c7-837f-4dcb-8b9c-1a34bfe0fe91.png)

The problem is, the file that is missing should be downloaded during the push of the certificates from Keyvault but this is not happening and ansible playbook crashes.

If we restart the waagent service, the file "nameexample.prv" will be downloaded and ansible will not crash anymore.

The final lines of the ansible code, will remove this file again from the VM. The next deployment will crash again.

We have two workarounds here:
FIRST- if we restart the waagent after the crash everything will run as expected
SECOND - if we don't delete the file after the ansible

MAIN PROBLEM - this has been working like this for last 8 months, but now we are getting this errors.

we don't understand why, the agent doesn't push all the file in KV and we always need to restart the service to do a "complete download" let's say.


 - Distro and Version: RedHat|RHEL|7.3|
 - WALinuxAgent version: 2.9.0.4

**Additional context**
I can give you an agent log from 31st of January 4:30PM issue :

<img width="1190" alt="image" src="https://user-images.githubusercontent.com/124268307/216373059-724d0fce-704d-408d-a166-db0100be89e2.png">

**Log file attached**

[waagent.log](https://github.com/Azure/WALinuxAgent/files/10570703/waagent.log)

### Additional contract requirements

When a goal state supplies a certificate, the agent must make its `.crt` and `.prv` artifacts available locally, including when the goal state is supplied through Fast Track. If either artifact is removed, a subsequent goal-state update must restore it without requiring an agent restart.
