Cognito-Idp: I see 'code_delivery_details' is nil when signingUp.
### Discussed in https://github.com/getmoto/moto/discussions/7701

<div type='discussions-op-text'>

<sup>Originally posted by **atharnoor2** May 16, 2024</sup>
I'm using moto via Docker and have setup Lambda, UserPool  and client. When I signup a new user in the pool, I see the `code_delivery_details` is always return as nil. Incase of ForgotPassword, it does turn `code_delivery_details` in response. Is this something not supported for signUp at the moment ?</div>

### Additional contract requirements

The Cognito-IdP `SignUp` response includes a `CodeDeliveryDetails` field whenever a verification code would be delivered to the user's verified email address or phone number, and omits it otherwise. Whether such a delivery applies depends on the user pool's `AccountRecoverySetting` and `AutoVerifiedAttributes`.

`CodeDeliveryDetails` is a mapping containing:
- `Destination`: the email address or phone number to which the verification code would be sent.
- `DeliveryMedium`: `"EMAIL"` when the code is delivered by email, or `"SMS"` when it is delivered by phone.
- `AttributeName`: `"email"` for email delivery or `"phone_number"` for phone delivery.

The `SignUp` response always includes `UserConfirmed` and `UserSub`.
