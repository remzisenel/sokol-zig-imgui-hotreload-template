# sokol-zig-imgui-hotreload-template

A template for **Zig** using **sokol-zig** and **cimgui** with support for **hot code reloading**.

This template offers two flexible build modes:

- **Static Build**: Statically link `sokol`, `cimgui`, and game logic into a single executable.
- **Hot Reload Build**: Build `sokol`, `cimgui`, and the game logic as **dynamic libraries** (`.so`, `.dylib`, or `.dll`) with **hot reload** support for the game logic.

---

## Features

- Two Build Modes (Static and Hot Reload)
- Hot Code Reloading (game code)
- State Persistence Across Reloads
- Soft Restart on Struct Layout Changes

---

## Usage

### Prerequisites

- **Zig** `0.14.0`

Tested platforms:
- macOS 

### Building

#### 1. Static Build
```bash
zig build static
```
This will compile everything (wrapper + sokol + cimgui + game logic) into a **single executable** located in the `static/` directory.

#### 2. Hot Reload Build
```bash
zig build hotreload
```
This builds:
- `libsokol_clib.dylib` / `libsokol_clib.so`
- `libcimgui_clib.dylib` / `libcimgui_clib.so`
- `libgame.dylib` / `libgame.so`
- a lightweight wrapper executable that loads these libraries,

Artifacts are placed inside the `hotreload/` directory.

#### 3. Default Install Step
```bash
zig build install
```
This will **build both** static and hotreload modes and place them in their respective folders (`static/` and `hotreload/`).

> Note: dynamic reloads are triggered either by filesystem ctime or hash changes (depending on how you wire it into FileWatcher).

---

## How Hot Reloading Works

- **Dynamic Linking**: Using Zig's `std.DynLib.open()`.
- **Memory Persistence**:
  - Allocator provided at game `init()`.
  - Game code allocates state using the allocator.
  - Ownership remains in the wrapper executable.
- **Layout Validation**:
  - Before reusing memory after reload, the wrapper checks `@sizeOf(GameState)`.
  - If size is different, perform a soft restart (dispose of state and reallocate initial state).

---

## Project Structure

```text
/zig-sokol-imgui-hotreload-template
├── build.zig.zon            # Zig package info
├── build.zig                # Build script
├── src/
│   ├── main_hr.zig          # Hot reloading wrapper entry
│   ├── main_static.zig      # Static wrapper entry
│   └── game/
│       └── root.zig         # Game code
└── README.md
```

---

## Contributing

Feel free to open issues or PRs! Suggestions for improving cross-platform support, reload robustness, or ergonomics are welcome.