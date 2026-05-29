# Packages Loader

String-based package loader for pesde-installed Roblox packages.

## Usage

```lua
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local require = require(ReplicatedStorage.Packages.Loader).load()

local BadgeUtils = require('BadgeUtils')
```

By default, the loader searches `ReplicatedStorage.Packages`. Pass explicit roots with `loader.load(...)` when testing or mounting packages somewhere else.
