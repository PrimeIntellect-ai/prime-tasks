Reminder. CountryId and CustomerId VO should not allow 0 value
### Is your feature request related to a problem?

As we noticed in this PR https://github.com/PrestaShop/PrestaShop/pull/25742 we should have a `NoCountryId` and a `NoCustomerId` VO to handle the fact that we unassociate them

It has been implement for many other VOs, however it was not doable in said PR because it was already very big and CountryId and CustomerId already accept 0 as input values, so it requires to refacto all their uses

### Describe the solution you'd like

- `CountryId` and `CustomerId` VOs don't accept 0 as input value anymore and trigger exception when such input is used in constructor
- we need a `NoCountryId` and `NoCustomerId` VO to handle the case for 0 value
- we need common interfaces for related VOs
- it might be worth checking other VOs to see if other have the same issue

### Additional contract requirements

- `PrestaShop\PrestaShop\Core\Domain\Country\ValueObject\CountryId` must reject `0` in its constructor by throwing `PrestaShop\PrestaShop\Core\Domain\Country\Exception\CountryConstraintException` with code `CountryConstraintException::INVALID_ID`.
- `PrestaShop\PrestaShop\Core\Domain\Customer\ValueObject\CustomerId` must reject `0` in its constructor by throwing `PrestaShop\PrestaShop\Core\Domain\Customer\Exception\CustomerConstraintException` with code `CustomerConstraintException::INVALID_ID`.
- `PrestaShop\PrestaShop\Core\Domain\State\ValueObject\StateId` must reject `0` in its constructor by throwing `PrestaShop\PrestaShop\Core\Domain\State\Exception\StateConstraintException` with code `StateConstraintException::INVALID_ID`.
- `PrestaShop\PrestaShop\Core\Domain\Country\ValueObject\NoCountryId` must exist and its `getValue()` must return `0`.
- `PrestaShop\PrestaShop\Core\Domain\Customer\ValueObject\NoCustomerId` must exist and its `getValue()` must return `0`.
- `PrestaShop\PrestaShop\Core\Domain\State\ValueObject\NoStateId` must exist and its `getValue()` must return `0`.
- Common interfaces: `CountryId` and `NoCountryId` implement `PrestaShop\PrestaShop\Core\Domain\Country\ValueObject\CountryIdInterface`; `CustomerId` and `NoCustomerId` implement `PrestaShop\PrestaShop\Core\Domain\Customer\ValueObject\CustomerIdInterface`; `StateId` and `NoStateId` implement `PrestaShop\PrestaShop\Core\Domain\State\ValueObject\StateIdInterface`. Each interface declares `getValue(): int`.


- - `CountryId` must reject `-10` in its constructor by throwing `CountryConstraintException` with code `CountryConstraintException::INVALID_ID`.
- `CustomerId` must reject `-10` in its constructor by throwing `CustomerConstraintException` with code `CustomerConstraintException::INVALID_ID`.
