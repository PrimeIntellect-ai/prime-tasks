coverage error if __typename is in the query
It seems that coverage throws error if the query contains the field `__typename` in the following line:
https://github.com/kamilkisiela/graphql-inspector/blob/e87c322703f305323cff947a156a5709877978c7/packages/core/src/coverage/index.ts#L66

Do you think it is OK to simple ignore it?
