Add documents with wrong primaryKey parameter should not add the primary key to the index
Steps

- Add these documents with the primary key parameter `title`
```
[ {
    "id": 2,
    "title": "Pride and Prejudice",
    "author": "Jane Austin",
    "genre": "romance",
    "price": 3.5
} ]
```
- Check the update: the update fails -> expected ✅
- Get the index: the primary key is added -> unexpected ❌
```
{
    "uid": "indexUID",
    "name": "indexUID",
    "createdAt": "2021-09-29T16:25:03.085943Z",
    "updatedAt": "2021-09-29T16:25:03.088458Z",
    "primaryKey": "title"
}
```
The primary key should not be added.

TLDR; When the first document addition does not work, the primary key passed as parameter should not be added to the index.

⚠️ Add tests
