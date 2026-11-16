Upgrade AWS SDK to 2.29.9
# Task Description

We need to upgrade the `software.amazon.awssdk:bom` dependency to version 2.23.7 as it includes some new AWS S3 methods we can use.

# Tasks

The following tasks will need to be carried out:
* [ ] Upgrade to v 2.29.9
* [ ] Run tests

# Task Relationships

This task:
* Is a sub-task of: #
* Depends on: #
* Is a follow-up of: #
* Relates to: #

# Useful Links

* [PutObjectRequest#ifNoneMatch](https://sdk.amazonaws.com/java/api/2.28.0/software/amazon/awssdk/services/s3/model/PutObjectRequest.html#ifNoneMatch()) -- with some future refactoring would allow us to reduce the api requests sent to check if a file exists or not.

# Help

* Our [chat channel](https://chat.carlspring.org/channel/s3fs-nio-community)
* Points of contact:
  * @carlspring
  * @steve-todorov

### Additional contract requirements

- Upgrade the `software.amazon.awssdk:bom` dependency to version `2.29.9`; this is the target version for the requested upgrade.
