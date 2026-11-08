Handle flattened data type in fields validator
The [flattened](https://www.elastic.co/guide/en/elasticsearch/reference/master/flattened.html) data type indexes an entire object as a single field. The tests are incorrectly expecting the leaf values of flattened fields to be part of the mapping.

Pipeline test output: <details>
FAILURE DETAILS:

aws/cloudtrail add-user-to-group-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.groupName" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail assume-role-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.durationSeconds" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.incomingTransitiveTags.Department" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.roleArn" is undefined
[3] field "aws.cloudtrail.flattened.request_parameters.roleSessionName" is undefined
[4] field "aws.cloudtrail.flattened.request_parameters.tags" is undefined
[5] field "aws.cloudtrail.flattened.request_parameters.transitiveTagKeys" is undefined
[6] field "aws.cloudtrail.flattened.response_elements.assumedRoleUser.arn" is undefined
[7] field "aws.cloudtrail.flattened.response_elements.assumedRoleUser.assumedRoleId" is undefined
[8] field "aws.cloudtrail.flattened.response_elements.credentials.accessKeyId" is undefined
[9] field "aws.cloudtrail.flattened.response_elements.credentials.expiration" is undefined
[10] field "aws.cloudtrail.flattened.response_elements.credentials.sessionToken" is undefined
[11] field "user_agent.os.full" is undefined
[12] field "user_agent.os.name" is undefined
[13] field "user_agent.os.version" is undefined
[14] field "user_agent.version" is undefined
aws/cloudtrail change-password-json.log:
[0] field "user_agent.version" is undefined
aws/cloudtrail console-login-json.log:
[0] field "aws.cloudtrail.flattened.additional_eventdata.LoginTo" is undefined
[1] field "aws.cloudtrail.flattened.additional_eventdata.MFAUsed" is undefined
[2] field "aws.cloudtrail.flattened.additional_eventdata.MobileVersion" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.ConsoleLogin" is undefined
[4] field "user_agent.os.full" is undefined
[5] field "user_agent.os.name" is undefined
[6] field "user_agent.os.version" is undefined
[7] field "user_agent.version" is undefined
aws/cloudtrail create-access-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
[1] field "aws.cloudtrail.flattened.response_elements.accessKey.accessKeyId" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.accessKey.createDate" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.accessKey.status" is undefined
[4] field "aws.cloudtrail.flattened.response_elements.accessKey.userName" is undefined
aws/cloudtrail create-group-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.groupName" is undefined
[1] field "aws.cloudtrail.flattened.response_elements.group.arn" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.group.createDate" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.group.groupId" is undefined
[4] field "aws.cloudtrail.flattened.response_elements.group.groupName" is undefined
[5] field "aws.cloudtrail.flattened.response_elements.group.path" is undefined
[6] field "user_agent.version" is undefined
aws/cloudtrail create-key-pair-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.keyName" is undefined
[1] field "aws.cloudtrail.flattened.response_elements.keyFingerprint" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.keyMaterial" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.keyName" is undefined
[4] field "user_agent.os.name" is undefined
aws/cloudtrail create-trail-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.enableLogFileValidation" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.includeGlobalServiceEvents" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.isMultiRegionTrail" is undefined
[3] field "aws.cloudtrail.flattened.request_parameters.isOrganizationTrail" is undefined
[4] field "aws.cloudtrail.flattened.request_parameters.kmsKeyId" is undefined
[5] field "aws.cloudtrail.flattened.request_parameters.name" is undefined
[6] field "aws.cloudtrail.flattened.request_parameters.s3BucketName" is undefined
[7] field "aws.cloudtrail.flattened.response_elements.includeGlobalServiceEvents" is undefined
[8] field "aws.cloudtrail.flattened.response_elements.isMultiRegionTrail" is undefined
[9] field "aws.cloudtrail.flattened.response_elements.isOrganizationTrail" is undefined
[10] field "aws.cloudtrail.flattened.response_elements.logFileValidationEnabled" is undefined
[11] field "aws.cloudtrail.flattened.response_elements.name" is undefined
[12] field "aws.cloudtrail.flattened.response_elements.s3BucketName" is undefined
[13] field "aws.cloudtrail.flattened.response_elements.trailARN" is undefined
[14] parsing field value failed: field "aws.cloudtrail.read_only"''s Go type, bool, does not match the expected field type: keyword
aws/cloudtrail create-user-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
[1] field "aws.cloudtrail.flattened.response_elements.user.arn" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.user.createDate" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.user.path" is undefined
[4] field "aws.cloudtrail.flattened.response_elements.user.userId" is undefined
[5] field "aws.cloudtrail.flattened.response_elements.user.userName" is undefined
[6] field "user_agent.os.name" is undefined
[7] field "user_agent.version" is undefined
aws/cloudtrail create-virtual-mfa-device-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.path" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.virtualMFADeviceName" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.virtualMFADevice.serialNumber" is undefined
aws/cloudtrail deactivate-mfa-device-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.serialNumber" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail delete-access-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.accessKeyId" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail delete-bucket-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.bucketName" is undefined
[1] field "user_agent.os.full" is undefined
[2] field "user_agent.os.name" is undefined
[3] field "user_agent.os.version" is undefined
[4] field "user_agent.version" is undefined
aws/cloudtrail delete-group-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.groupName" is undefined
[1] field "user_agent.version" is undefined
aws/cloudtrail delete-ssh-public-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.sSHPublicKeyId" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail delete-trail-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.name" is undefined
[1] field "user_agent.version" is undefined
[2] parsing field value failed: field "aws.cloudtrail.read_only"''s Go type, bool, does not match the expected field type: keyword
aws/cloudtrail delete-user-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail delete-virtual-mfa-device-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.serialNumber" is undefined
aws/cloudtrail enable-mfa-device-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.serialNumber" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail remove-user-from-group-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.groupName" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail start-logging-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.name" is undefined
[1] parsing field value failed: field "aws.cloudtrail.read_only"''s Go type, bool, does not match the expected field type: keyword
aws/cloudtrail stop-logging-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.name" is undefined
[1] parsing field value failed: field "aws.cloudtrail.read_only"''s Go type, bool, does not match the expected field type: keyword
aws/cloudtrail update-access-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.accessKeyId" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.status" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail update-accout-password-policy-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.allowUsersToChangePassword" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.minimumPasswordLength" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.requireLowercaseCharacters" is undefined
[3] field "aws.cloudtrail.flattened.request_parameters.requireNumbers" is undefined
[4] field "aws.cloudtrail.flattened.request_parameters.requireSymbols" is undefined
[5] field "aws.cloudtrail.flattened.request_parameters.requireUppercaseCharacters" is undefined
aws/cloudtrail update-group-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.groupName" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.newGroupName" is undefined
[2] field "user_agent.version" is undefined
aws/cloudtrail update-login-profile-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail update-ssh-public-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.sSHPublicKeyId" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.status" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
aws/cloudtrail update-trail-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.enableLogFileValidation" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.isMultiRegionTrail" is undefined
[2] field "aws.cloudtrail.flattened.request_parameters.kmsKeyId" is undefined
[3] field "aws.cloudtrail.flattened.request_parameters.name" is undefined
[4] field "aws.cloudtrail.flattened.request_parameters.s3BucketName" is undefined
[5] field "aws.cloudtrail.flattened.request_parameters.snsTopicName" is undefined
[6] field "aws.cloudtrail.flattened.response_elements.includeGlobalServiceEvents" is undefined
[7] field "aws.cloudtrail.flattened.response_elements.isMultiRegionTrail" is undefined
[8] field "aws.cloudtrail.flattened.response_elements.isOrganizationTrail" is undefined
[9] field "aws.cloudtrail.flattened.response_elements.logFileValidationEnabled" is undefined
[10] field "aws.cloudtrail.flattened.response_elements.name" is undefined
[11] field "aws.cloudtrail.flattened.response_elements.s3BucketName" is undefined
[12] field "aws.cloudtrail.flattened.response_elements.snsTopicARN" is undefined
[13] field "aws.cloudtrail.flattened.response_elements.snsTopicName" is undefined
[14] field "aws.cloudtrail.flattened.response_elements.trailARN" is undefined
[15] field "user_agent.os.name" is undefined
[16] field "user_agent.version" is undefined
[17] parsing field value failed: field "aws.cloudtrail.read_only"''s Go type, bool, does not match the expected field type: keyword
aws/cloudtrail update-user-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.newUserName" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
[2] field "error.message" is undefined
[3] field "json" is undefined
[4] field "user_agent.version" is undefined
aws/cloudtrail upload-ssh-public-key-json.log:
[0] field "aws.cloudtrail.flattened.request_parameters.sSHPublicKeyBody" is undefined
[1] field "aws.cloudtrail.flattened.request_parameters.userName" is undefined
[2] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.fingerprint" is undefined
[3] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.sSHPublicKeyBody" is undefined
[4] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.sSHPublicKeyId" is undefined
[5] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.status" is undefined
[6] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.uploadDate" is undefined
[7] field "aws.cloudtrail.flattened.response_elements.sSHPublicKey.userName" is undefined
--- Test results for package: aws - END   ---
Done
</details>
