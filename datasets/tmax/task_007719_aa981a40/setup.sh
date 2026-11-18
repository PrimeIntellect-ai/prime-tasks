#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo

    cat << 'EOF' > /home/user/repo/inventory.proto
syntax = "proto3";

package inventory;

service InventoryService {
  rpc GetItem (GetItemRequest) returns (ItemResponse);
  rpc ListItems (ListItemsRequest) returns (ItemListResponse);
  rpc DeleteItem (DeleteItemRequest) returns (DeleteResponse);
}

message GetItemRequest {
  string id = 1;
}

message ListItemsRequest {
  int32 page_size = 1;
  string page_token = 2;
}

message DeleteItemRequest {
  string id = 1;
}

message ItemResponse {
  string id = 1;
  string name = 2;
  int32 quantity = 3;
}

message ItemListResponse {
  repeated ItemResponse items = 1;
  string next_page_token = 2;
}

message DeleteResponse {
  bool success = 1;
}
EOF

    cat << 'EOF' > /home/user/repo/pr.patch
--- inventory.proto
+++ inventory.proto
@@ -6,6 +6,8 @@
   rpc GetItem (GetItemRequest) returns (ItemResponse);
   rpc ListItems (ListItemsRequest) returns (ItemListResponse);
   rpc DeleteItem (DeleteItemRequest) returns (DeleteResponse);
+  rpc CreateItem (CreateItemRequest) returns (ItemResponse)
+  rpc UpdateItem (UpdateItemRequest) returns (ItemResponse);
 }

 message GetItemRequest {
@@ -34,3 +36,13 @@
 message DeleteResponse {
   bool success = 1;
 }
+
+message CreateItemRequest {
+  string name = 1;
+  int32 quantity = 2;
+}
+
+message UpdateItemRequest {
+  string id = 1;
+  int32 quantity = 2;
+}
EOF

    chmod -R 777 /home/user
