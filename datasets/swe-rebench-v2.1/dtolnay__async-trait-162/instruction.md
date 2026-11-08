Not compatible with tokio::select!.
before expand:
```rust
use async_trait::async_trait;
use std::sync::Arc;

#[async_trait]
trait MyTrait {
    async fn my_fn(self: Arc<Self>);
}

struct MyStruct {
    test_member: bool,
}

#[async_trait]
impl MyTrait for MyStruct {
    async fn my_fn(self: Arc<Self>) {
        tokio::select! {
            _ = async {
                println!("{}", self.test_member);
            } => {}
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    Arc::new(MyStruct { test_member: true }).my_fn().await;

    Ok(())
}
```

after expand:
```rust
use std::sync::Arc;

trait TestTrait {
    #[must_use]
    #[allow(clippy::type_complexity, clippy::type_repetition_in_bounds)]
    fn my_fn<'async_trait>(
        self: Arc<Self>,
    ) -> ::core::pin::Pin<
        Box<dyn ::core::future::Future<Output = ()> + ::core::marker::Send + 'async_trait>,
    >
    where
        Self: 'async_trait;
}
struct TestStruct {
    test_member: bool,
}
impl TestTrait for TestStruct {
    #[allow(
        clippy::let_unit_value,
        clippy::type_complexity,
        clippy::type_repetition_in_bounds,
        clippy::used_underscore_binding
    )]
    fn my_fn<'async_trait>(
        self: Arc<Self>,
    ) -> ::core::pin::Pin<
        Box<dyn ::core::future::Future<Output = ()> + ::core::marker::Send + 'async_trait>,
    >
    where
        Self: 'async_trait,
    {
        Box::pin(async move {
            [HIDDEN]
            let _: () = {
                {
                    mod util {
                        pub(super) enum Out<_0> {
                            _0(_0),
                            Disabled,
                        }
                        pub(super) type Mask = u8;
                    }
                    use ::tokio::macros::support::Future;
                    use ::tokio::macros::support::Pin;
                    use ::tokio::macros::support::Poll::{Pending, Ready};
                    const BRANCHES: u32 = 1;
                    let mut disabled: util::Mask = Default::default();
                    if !true {
                        let mask = 1 << 0;
                        disabled |= mask;
                    }
                    let mut output = {
                        let mut futures = (async {
                            println!("{}", self.test_member);
                        },);
                        ::tokio::macros::support::poll_fn(|cx| {
                            let mut is_pending = false;
                            let start = { ::tokio::macros::support::thread_rng_n(BRANCHES) };
                            for i in 0..BRANCHES {
                                let branch;
                                #[allow(clippy::modulo_one)]
                                {
                                    branch = (start + i) % BRANCHES;
                                }
                                match branch {
                                    #[allow(unreachable_code)]
                                    0 => {
                                        let mask = 1 << branch;
                                        if disabled & mask == mask {
                                            continue;
                                        }
                                        let (fut, ..) = &mut futures;
                                        let mut fut = unsafe { Pin::new_unchecked(fut) };
                                        let out = match fut.poll(cx) {
                                            Ready(out) => out,
                                            Pending => {
                                                is_pending = true;
                                                continue;
                                            }
                                        };
                                        disabled |= mask;
                                        #[allow(unused_variables)]
                                        #[allow(unused_mut)]
                                        match &out {
                                            _ => {}
                                            _ => continue,
                                        }
                                        return Ready(util::Out::_0(out));
                                    }
                                    _ => {
                                        unreachable!()
                                    }
                                }
                            }
                            if is_pending {
                                Pending
                            } else {
                                Ready(util::Out::Disabled)
                            }
                        })
                        .await
                    };
                    match output {
                        util::Out::_0(_) => {}
                        util::Out::Disabled => unreachable!(),
                        _ => unreachable!(),
                    }
                }
            };
        })
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    Arc::new(TestStruct { test_member: true }).my_fn().await;

    Ok(())
}
```

![image](https://user-images.githubusercontent.com/32861476/115103747-e87ef300-9f86-11eb-8553-5f51b8343361.png)
[HIDDEN]

### Additional contract requirements

- An `#[async_trait]` method with an `Arc<Self>` receiver must remain usable when its body references `self` inside a select macro such as `tokio::select!`.
