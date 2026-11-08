Incorrect behaviour when using two states
# System configuration

**OS**: Windows 11
**Bevy**:  0.10.1 (from crates.io)

`rustc --version`: `rustc 1.68.2 (9eb3afe9e 2023-03-27)`
`rustup default`: `stable-x86_64-pc-windows-msvc`

# What versions the problems happens on

This problem happens with `bevy_asset_loader 0.16` and the latest version on the github (when I fetched it the latest commit was 5cd90672eb5b9a8a2127bd225c3f9d3a57c963d4)

# The issue

I have been trying to implement some multistep loading in my game prototype by having two states -- one that tracks loading and the other tracks the game state.

It seems that `bevy_asset_loader` does something incorrect in such configurations and the assets don't get loaded.

# Minimal examples

Program 1 (Single probing)

```rust
use bevy::prelude::*;
use bevy_asset_loader::prelude::{AssetCollection, LoadingStateAppExt, LoadingState};

#[derive(Clone, Copy, Debug, States, Default, PartialEq, Eq, Hash)]
enum Game {
    #[default]
    Booting,
    Loading,
    Play,
}

#[derive(Clone, Copy, Debug, States, Default, PartialEq, Eq, Hash)]
enum Loading {
    #[default]
    Done,
    Loading,
    Finalize,
}

#[derive(Resource, Default)]
pub struct Probe;

#[derive(Resource, AssetCollection)]
pub struct Collection1 {
    #[asset(path = "bevy1.png")]
    _img: Handle<Image>,
}


#[derive(Resource, AssetCollection)]
pub struct Collection2 {
    #[asset(path = "bevy2.png")]
    _img: Handle<Image>,
}

fn probe(_res: Res<Collection2>) {}

fn transition1(
    mut next_l: ResMut<NextState<Loading>>,
) {
    next_l.0 = Some(Loading::Loading);
}

fn transition2(
    mut next_g: ResMut<NextState<Game>>,
    mut next_l: ResMut<NextState<Loading>>,
) {
    next_g.0 = Some(Game::Play);
    next_l.0 = Some(Loading::Done);
}

fn main() {
    App::new()
    .add_plugins(DefaultPlugins)
    .add_state::<Loading>()
    .add_state::<Game>()
    .add_loading_state(
        LoadingState::new(Game::Booting)
        .continue_to_state(Game::Loading)
    )
    .add_collection_to_loading_state::<_, Collection1>(Game::Booting)
    .add_loading_state(
        LoadingState::new(Loading::Loading)
        .continue_to_state(Loading::Finalize)
    )
    .add_collection_to_loading_state::<_, Collection2>(Loading::Loading)
    .add_system(transition1.in_schedule(OnEnter(Game::Loading)))
    .add_system(transition2.in_schedule(OnEnter(Loading::Finalize)))
    .add_system(probe.in_schedule(OnEnter(Game::Play)))
    .run();
}
```

Program 2 (repeated probing)

```rust
use bevy::prelude::*;
use bevy_asset_loader::prelude::{AssetCollection, LoadingStateAppExt, LoadingState};

#[derive(Clone, Copy, Debug, States, Default, PartialEq, Eq, Hash)]
enum Game {
    #[default]
    Booting,
    Loading,
    Play,
}

#[derive(Clone, Copy, Debug, States, Default, PartialEq, Eq, Hash)]
enum Loading {
    #[default]
    Done,
    Loading,
    Finalize,
}

#[derive(Resource, Default)]
pub struct Probe;

#[derive(Resource, AssetCollection)]
pub struct Collection1 {
    #[asset(path = "bevy1.png")]
    _img: Handle<Image>,
}


#[derive(Resource, AssetCollection)]
pub struct Collection2 {
    #[asset(path = "bevy2.png")]
    _img: Handle<Image>,
}

fn probe(res: Option<Res<Collection2>>) {
    info!("probe: {}", res.is_some());
}

fn transition1(
    mut next_l: ResMut<NextState<Loading>>,
) {
    next_l.0 = Some(Loading::Loading);
}

fn transition2(
    mut next_g: ResMut<NextState<Game>>,
    mut next_l: ResMut<NextState<Loading>>,
) {
    next_g.0 = Some(Game::Play);
    next_l.0 = Some(Loading::Done);
}

fn main() {
    App::new()
    .add_plugins(DefaultPlugins)
    .add_state::<Loading>()
    .add_state::<Game>()
    .add_loading_state(
        LoadingState::new(Game::Booting)
        .continue_to_state(Game::Loading)
    )
    .add_collection_to_loading_state::<_, Collection1>(Game::Booting)
    .add_loading_state(
        LoadingState::new(Loading::Loading)
        .continue_to_state(Loading::Finalize)
    )
    .add_collection_to_loading_state::<_, Collection2>(Loading::Loading)
    .add_system(transition1.in_schedule(OnEnter(Game::Loading)))
    .add_system(transition2.in_schedule(OnEnter(Loading::Finalize)))
    .add_system(probe.in_set(OnUpdate(Game::Play)))
    .run();
}
```

# What you expected to happen

The first program shouldn't crash. The second program should have printed `probe: true`

# What happened

The first program crashed

```
     Running `target\debug\bevy_ald.exe`
2023-04-10T12:07:27.081547Z  INFO bevy_asset_loader::loading_state::systems: Loading state 'Loading' is done
thread 'Compute Task Pool (7)' panicked at 'Resource requested by bevy_ald::probe does not exist: bevy_ald::Collection', bevy_ecs-0.10.1\src\system\system_param.rs:460:17
```

The second program not only prints `false`, but also never prints `true`

```
     Running `target\debug\bevy_ald.exe`
2023-04-10T12:06:12.621932Z  INFO bevy_asset_loader::loading_state::systems: Loading state 'Loading' is done
2023-04-10T12:06:12.623797Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.625324Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.627005Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.628147Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.629495Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.630807Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.632035Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.633344Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.634580Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.635828Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.637343Z  INFO bevy_ald: probe: false
2023-04-10T12:06:12.638524Z  INFO bevy_ald: probe: false
```
