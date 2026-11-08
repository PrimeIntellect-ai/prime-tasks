Bundling converts date-time examples to OrderedMap {}


**To Reproduce**
![Screenshot from 2021-11-29 14-27-31](https://user-images.githubusercontent.com/19946948/143837645-591f6800-9043-4f11-9d4d-cce22814b1e8.png)

CMD: `openapi bundle test.yaml -o final_output.yaml`

**Expected behavior**
![ss1](https://user-images.githubusercontent.com/19946948/143838003-13741ec7-6109-403e-bff8-ca62d4db7d84.png)

**Actual Behaviour**
![Screenshot from 2021-11-29 14-31-53](https://user-images.githubusercontent.com/19946948/143838172-74ebf9ae-1942-446e-9dcc-9df26c50ff00.png)

** reason **
post bundling qoutes from the api documentation gets removed..
![Screenshot from 2021-11-29 14-37-15](https://user-images.githubusercontent.com/19946948/143840329-d8ba71dd-9e6e-4364-8013-116e7b11d70e.png)

### Additional contract requirements

- Bundling must preserve date-time examples as YAML scalar values rather than converting them to `OrderedMap {}`.
- When serializing the date-time string `2022-01-21T11:29:56.694Z`, the YAML output must contain the exact single-quoted scalar `date: '2022-01-21T11:29:56.694Z'`.
