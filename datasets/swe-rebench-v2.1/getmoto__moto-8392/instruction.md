Limit shouldn't be applied before Filter when listing users
Using the current version of moto, if you run cognito-idp's list_users() with both Limit and Filter keywords, the limit is applied before the filter. So, if you are searching for a user with a particular sub that isn't the first item in the user pool, and you set Limit to 1, then it will always fail to find it because [HIDDEN]

### Additional contract requirements

- When `Filter` and `Limit` are both supplied to `list_users`, apply the filter before the limit so a matching user beyond the unfiltered first page is not omitted.
