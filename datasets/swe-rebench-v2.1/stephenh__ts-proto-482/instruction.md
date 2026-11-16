Snake to Camel unexpected result
I have a proto file like this
```proto
syntax = "proto3";

package sso.v2;

message Client {
    string clientI_d = 1;
    string client_secret = 2;
}

message LoginRequest {
    string redirectUR_i = 12;
}
```

**after**:
```bash
protoc --plugin=./node_modules/.bin/protoc-gen-ts_proto --ts_proto_opt=nestJs=true --ts_proto_opt=env=node --ts_proto_opt=addGrpcMetadata=true --ts_proto_opt=useExactTypes=false --ts_proto_opt=useOptionals=messages --ts_proto_opt=forceLong=string --ts_proto_out=. *.proto
```
**produce**:
```typescript
/* eslint-disable */
import { util, configure } from "protobufjs/minimal";
import * as Long from "long";

export const protobufPackage = "sso.v2";

export interface Client {
  clientiD: string;
  clientSecret: string;
}

export interface LoginRequest {
  redirecturI: string;
}

export const SSO_V2_PACKAGE_NAME = "sso.v2";

// If you get a compile-error about 'Constructor<Long> and ... have no overlap',
// add '--ts_proto_opt=esModuleInterop=true' as a flag when calling 'protoc'.
if (util.Long !== Long) {
  util.Long = Long as any;
  configure();
}

```

the expected result should be `clientID` instead of `clientiD` and `redirectURI` instead of `redirecturI`
