Table comment is always parsed as CommentDef::WithoutEq
Say I have the following table:

```sql
CREATE TABLE users (
  user_id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '口座内部ID',
  user_name VARCHAR(255) NOT NULL,
  PRIMARY KEY (user_id),
) COMMENT = 'users of the service';
```

And I parse and re-build it with sqlparser like this:

```rust
use sqlparser::{
    dialect,
    parser::Parser,
};

pub fn test() {
    let dialect = dialect::GenericDialect {};
    let parsed = Parser::parse_sql(&dialect, r#"
        CREATE TABLE users (
            user_id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '口座内部ID',
            user_name VARCHAR(255) NOT NULL,
            PRIMARY KEY (user_id)
        ) COMMENT = 'users of the service';
    "#);

    let binding = parsed.unwrap();
    let stmt = binding.first().unwrap();

    println!("{}", stmt.to_string());
}
```

then I got the following result:

```
CREATE TABLE users (user_id INT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '口座内部ID', user_name VARCHAR(255) NOT NULL, PRIMARY KEY (user_id)) COMMENT 'users of the service'
```

It looks like a table comment is always treated as `CommentDef::WithoutEq` here.

https://github.com/apache/datafusion-sqlparser-rs/blob/main/src/parser/mod.rs#L5877
