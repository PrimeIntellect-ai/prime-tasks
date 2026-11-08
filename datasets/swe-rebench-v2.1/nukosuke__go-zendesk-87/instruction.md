Add support for brand CRUD
https://developer.zendesk.com/rest_api/docs/support/brands

- [x] Create #62
- [x] Read
- [x] Update
- [x] Delete

### Additional contract requirements

- In package `zendesk`, expose these methods on `*Client`:
  - `GetBrand(brandID int64) (Brand, error)` to read a brand.
  - `UpdateBrand(brandID int64, brand Brand) (Brand, error)` to update a brand.
  - `DeleteBrand(brandID int64) error` to delete a brand.
