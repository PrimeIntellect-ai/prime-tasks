Deserialization error occurs when enum member contains multiple values
The following is a very simple use case. my_box can be serialized into toml, but this toml cannot be parsed back.

``` rust
    #[derive(Debug, Serialize, Deserialize)]
    enum AB {
        A(i32, i32),
        B(String, String),
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct Box {
        inner: Vec<AB>,
    }

    #[test]
    fn toml_test() {
        let my_box = Box {
            inner: vec![
                AB::A(1, 1),
                AB::B("2".to_string(), "2".to_string()),
            ],
        };

        println!("===== now serialize =====");

        // serialize my_box to a TOML string
        match toml::to_string(&my_box) {
            Ok(v) => {
                println!("ser ok!\n{}", &v);

                println!("===== now deserialize =====");

                // deserialize the TOML string back to my_box
                match toml::from_str::<Box>(&v) {
                    Ok(v) => println!("de ok!\n{:?}", v),
                    Err(e) => println!("de err!\n{}", e),
                }
            }
            Err(e) => println!("ser err!\n{}", e),
        }
    }
```

output
```
===== now serialize =====
ser ok!
inner = [[1, 1], ["2", "2"]]

===== now deserialize =====
de err!
TOML parse error at line 1, column 10
  |
1 | inner = [[1, 1], ["2", "2"]]
  |          ^^^^^^
wanted string or table
```

---

Then I wrapped the two values of each member into a tuple and it worked fine

``` rust
#[derive(Debug, Serialize, Deserialize)]
    enum AB {
        A((i32, i32)),
        B((String, String)),
    }

    #[derive(Debug, Serialize, Deserialize)]
    struct Box {
        inner: Vec<AB>,
    }

    #[test]
    fn toml_test() {
        let my_box = Box {
            inner: vec![
                AB::A((1, 1)),
                AB::B(("2".to_string(), "2".to_string())),
            ],
        };

        println!("===== now serialize =====");

        // serialize my_box to a TOML string
        match toml::to_string(&my_box) {
            Ok(v) => {
                println!("ser ok!\n{}", &v);

                println!("===== now deserialize =====");

                // deserialize the TOML string back to my_box
                match toml::from_str::<Box>(&v) {
                    Ok(v) => println!("de ok!\n{:?}", v),
                    Err(e) => println!("de err!\n{}", e),
                }
            }
            Err(e) => println!("ser err!\n{}", e),
        }
    }
```

output
```
===== now serialize =====
ser ok!
[[inner]]
A = [1, 1]

[[inner]]
B = ["2", "2"]

===== now deserialize =====
de ok!
Box { inner: [A((1, 1)), B(("2", "2"))] }
```

---

After that, I changed the enum parameters to named form, and even the serialization went wrong.

``` rust
#[derive(Debug, Serialize, Deserialize)]
enum AB {
    A { v1: i32, v2: i32 },
    B { s1: String, s2: String },
}

#[derive(Debug, Serialize, Deserialize)]
struct Box {
    inner: Vec<AB>,
}

#[test]
fn toml_test() {
    let my_box = Box {
        inner: vec![
            AB::A { v1: 1, v2: 2 },
            AB::B { s1: "a".to_string(), s2: "b".to_string() },
        ],
    };

    println!("original:\n{:?}", &my_box);

    println!("===== now serialize =====");

    // serialize my_box to a TOML string
    match toml::to_string(&my_box) {
        Ok(v) => {
            println!("ser ok!\n{}", &v);

            println!("===== now deserialize =====");

            // deserialize the TOML string back to my_box
            match toml::from_str::<Box>(&v) {
                Ok(v) => println!("de ok!\n{:?}", v),
                Err(e) => println!("de err!\n{}", e),
            }
        }
        Err(e) => println!("ser err!\n{}", e),
    }
}
```

output
```
original:
Box { inner: [A { v1: 1, v2: 2 }, B { s1: "a", s2: "b" }] }
===== now serialize =====
ser err!
unsupported AB type
```

### Additional contract requirements

Tuple enum variants containing multiple values must serialize to valid TOML and deserialize back to the original enum value. Named-field enum variants must also serialize to valid TOML and deserialize back to the original enum value.
