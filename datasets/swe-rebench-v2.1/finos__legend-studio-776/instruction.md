Bug: Missing support for local properties in relational mappings
### Similar issues

- [X] I have searched and found no existing similar issues

### How are you using Studio?

Legend Studio

### Current and expected behavior

Legend Engine allows users to define local properties in context of mapping. These properties are specifically useful in context of cross store relationships where adding the property in model is not ideal for modelling the business concept.

Engine supports local properties in context of relational mapping but studio does not support it yet.

Note : Studio does support local properties in context of M2M mapping

Below code currently throws an error - ```Can't build graph: Local mapping property is not supported```
Ideally studio should be able to compile below code

### Steps to reproduce

_No response_

### Model data

```text
###Relational
Database demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb
(
  Table productTable
  (
    productId VARCHAR(100) PRIMARY KEY,
    productName VARCHAR(100),
    description VARCHAR(1000)
  )
  Table synonymTable
  (
    synonymId INTEGER PRIMARY KEY,
    productId VARCHAR(100),
    type VARCHAR(200),
    name VARCHAR(200)
  )

  Join productTable_synonymTable(productTable.productId = synonymTable.productId)
)

###Pure

Enum demo::XStore::graphFetch::inMemoryAndRelational::models::SynonymType
{
  CUSIP,
  ISIN
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::T_Trade
{
  prodId: String[1];
  tradeId: Integer[1];
  traderKerb: String[0..1];
  quantity: Integer[1];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::S_TradesWrapper
{
  s_trades: demo::XStore::graphFetch::inMemoryAndRelational::models::S_Trade[*];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::Trade
{
  tradeId: Integer[1];
  traderKerb: String[0..1];
  quantity: Integer[1];
  productName() {$this.product.productName}: String[0..1];
  justProduct() {$this.product}: demo::XStore::graphFetch::inMemoryAndRelational::models::Product[0..1];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::Product
{
  productId: String[1];
  productName: String[1];
  description: String[1];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::TradeEvent
{
  eventId: String[1];
  description: String[1];
  timestamp: DateTime[1];
}


Class demo::XStore::graphFetch::inMemoryAndRelational::models::S_Trade
{
  s_tradeId: Integer[1];
  s_traderDetails: String[1];
  s_tradeDetails: String[1];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::Synonym
{
  name: String[1];
  type: demo::XStore::graphFetch::inMemoryAndRelational::models::SynonymType[1];
}

Class demo::XStore::graphFetch::inMemoryAndRelational::models::Trader
{
  kerberos: String[1];
  firstName: String[1];
  lastName: String[1];
}

Association demo::XStore::graphFetch::inMemoryAndRelational::models::Trade_Trader
{
  trader: demo::XStore::graphFetch::inMemoryAndRelational::models::Trader[1];
  trades: demo::XStore::graphFetch::inMemoryAndRelational::models::Trade[*];
}
Association demo::XStore::graphFetch::inMemoryAndRelational::models::T_Trade_Product
{
  product: demo::XStore::graphFetch::inMemoryAndRelational::models::Product[1];
  t_trades: demo::XStore::graphFetch::inMemoryAndRelational::models::T_Trade[*];
}

Association demo::XStore::graphFetch::inMemoryAndRelational::models::Product_Synonym
{
  product: demo::XStore::graphFetch::inMemoryAndRelational::models::Product[1];
  synonyms: demo::XStore::graphFetch::inMemoryAndRelational::models::Synonym[*];
}

Association demo::XStore::graphFetch::inMemoryAndRelational::models::Trade_Product
{
  product: demo::XStore::graphFetch::inMemoryAndRelational::models::Product[1];
  trades: demo::XStore::graphFetch::inMemoryAndRelational::models::Trade[*];
}

Association demo::XStore::graphFetch::inMemoryAndRelational::models::Trade_TradeEvent
{
  tradeEvents: demo::XStore::graphFetch::inMemoryAndRelational::models::TradeEvent[*];
  trade: demo::XStore::graphFetch::inMemoryAndRelational::models::Trade[1];
}
Association demo::XStore::graphFetch::inMemoryAndRelational::models::T_Trade_Trader
{
  trader: demo::XStore::graphFetch::inMemoryAndRelational::models::Trader[1];
  t_trades: demo::XStore::graphFetch::inMemoryAndRelational::models::T_Trade[*];
}


###Mapping
Mapping demo::XStore::graphFetch::inMemoryAndRelational::mappings::InMemoryAndRelationalCrossStoreMapping1
(
  demo::XStore::graphFetch::inMemoryAndRelational::models::Trade[trade_set]: Pure
  {
    ~src demo::XStore::graphFetch::inMemoryAndRelational::models::S_Trade
    tradeId: $src.s_tradeId,
    +prodId: String[1]: $src.s_tradeDetails->split(':')->at(0),
    quantity: $src.s_tradeDetails->split(':')->at(1)->parseInteger()
  }
  demo::XStore::graphFetch::inMemoryAndRelational::models::Product[prod_set]: Relational
  {
    ~primaryKey
    (
      [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable.productId
    )
    ~mainTable [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable

    +local : String[1] : [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable.productName,
    productId: [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable.productId,
    productName: [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable.productName,
    description: [demo::XStore::graphFetch::inMemoryAndRelational::database::inMemoryAndRelationalDb]productTable.description
  }

  demo::XStore::graphFetch::inMemoryAndRelational::models::Trade_Product: XStore
  {
    product[trade_set, prod_set]: $this.prodId == $that.productId,
    trades[prod_set, trade_set]: $this.productId == $that.prodId
  }
)
```


### Environment

```text
(no information provided)
```


### Possible solution and workaround

_No response_

### Contribution

- [ ] I would like to work on the fix for this issue
