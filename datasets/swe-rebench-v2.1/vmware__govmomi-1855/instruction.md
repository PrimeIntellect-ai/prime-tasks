vcsim - error adding disk on different datastore
When attempting a ReconfigVM_Task to add a disk on a different datastore, I receive the following error:

```xml
            <error>
              <fault XMLSchema-instance:type="FileFault">
                <file>/tmp/govcsim-DC0-LocalDS_2-353672936/test-vm2/test-vm2.vmdk</file>
              </fault>

              <localizedMessage>*types.FileFault</localizedMessage>
            </error>
```

The task request looks like:
```xml

<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
  <ReconfigVM_Task xmlns="urn:vim25">
    <_this type="VirtualMachine">vm-65</_this>
      <spec xsi:type="VirtualMachineConfigSpec">
          <numCPUs>2</numCPUs>
          <numCoresPerSocket>1</numCoresPerSocket>
          <deviceChange xsi:type="VirtualDeviceConfigSpec">
            <operation>edit</operation>
            <device xsi:type="VirtualDisk"><key>206</key><deviceInfo xsi:type="Description"><label>disk-205-0</label><summary>1,048,576 KB</summary></deviceInfo><backing xsi:type="VirtualDiskFlatVer2BackingInfo"><fileName>[LocalDS_1] test-vm2/test-vm2.vmdk</fileName><datastore type="Datastore">/tmp/govcsim-DC0-LocalDS_1-553967510@folder-5</datastore><diskMode>persistent</diskMode><thinProvisioned>0</thinProvisioned><eagerlyScrub>0</eagerlyScrub></backing><controllerKey>205</controllerKey><unitNumber>0</unitNumber><capacityInKB>2097152</capacityInKB></device></deviceChange><deviceChange xsi:type="VirtualDeviceConfigSpec"><operation>add</operation><fileOperation>create</fileOperation><device xsi:type="VirtualDisk"><key>-2</key><backing xsi:type="VirtualDiskFlatVer2BackingInfo"><fileName>[LocalDS_2]</fileName><diskMode>persistent</diskMode><thinProvisioned>0</thinProvisioned></backing><controllerKey>205</controllerKey><unitNumber>1</unitNumber><capacityInKB>2097152</capacityInKB></device>
          </deviceChange>
       </spec>
    </ReconfigVM_Task>
  </env:Body>
</env:Envelope>
```


I believe this may be caused by 488205f04de03d3b84556d2a4661f1ded084b00d.  When I reverted to 1f52ede5c89479e36b5edd310740b649cb574e66, my tests started working again.
