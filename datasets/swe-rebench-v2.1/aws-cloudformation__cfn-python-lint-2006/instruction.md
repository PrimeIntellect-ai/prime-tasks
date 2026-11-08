cfn-lint 0.49.1 does not catch `/` as an invalid character in a Mapping element name
*cfn-lint version: cfn-lint 0.49.1*

*cfn-lint did not catch `/` as an invalid character in a Mapping element name*

cfn-lint passed successfully with this mapping included in the template:
```yaml
Mappings:
  NameServers:
    10.90.0.0/16:
      NameServer1: 10.90.0.10
      NameServer2: 10.90.4.10
    10.91.0.0/16:
      NameServer1: 10.91.0.10
      NameServer2: 10.91.4.10
```

However AWS rejected it:
> Template format error: Mappings element name '10.93.0.0/16' must be non-empty and can contain only alphanumerics, '-' or '.'

![Screen Shot 2021-05-12 at 11 34 41](https://user-images.githubusercontent.com/7205587/117905164-0e917c00-b316-11eb-8132-2da240ff892a.png)
