# nvim-discordrpc
No nonsense, no configuration, no external dependencies, Discord rich presence for Neovim.

Core is copypasted from my menu state Garry's Mod rich presence (that I need to publish at some point) converted to
Neovim functions.

## Installation
Add `wrldspawn/nvim-discordrpc` to your favorite plugin manager

### lazy.nvim
```lua
{
    "wrldspawn/nvim-discordrpc",
    lazy = false,
}
```

## Credits
- [vyfor/cord.nvim](https://github.com/vyfor/cord.nvim) and [vyfor/icons](https://github.com/vyfor/icons) - Icons, filetype and filename mappings
- [EpicBird/discord.nvim](https://github.com/EpicBirb/discord.nvim) - Reference for converting connection logic
- [iryont/lua-struct](https://github.com/iryont/lua-struct) - Redistributed library
- [tcjennings/LUA-RFC-4122-UUID-Generator](https://github.com/tcjennings/LUA-RFC-4122-UUID-Generator) - Redistributed library
