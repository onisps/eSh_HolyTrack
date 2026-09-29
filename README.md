# eSh HolyTrack

**Tracks your Holy Priest HoTs (Renew, Prayer of Mending, and custom spells) as animated bars.**

- ✅ Embedded LibSharedMedia‑3.0 – pick any texture (same as Quartz/ElvUI) without needing a separate addon.
- ✅ Per‑profile settings – switch between characters or setups instantly.
- ✅ Scrolling watch‑list UI in the Interface Options panel – add spells by ID, enable/disable, change colour, delete.
- ✅ Grow direction – bars can grow upward (default) or downward.
- ✅ Lock/unlock – drag the gold‑bordered mover to reposition; hide it when locked.
- ✅ Show pets – optionally include pet units in the scan.
- ✅ Combat‑safe – all frames are pre‑created at login; no secure taint on raid frames.
- ✅ Tooltips – hover a bar to see the standard WoW aura tooltip.
- ✅ Slash commands – `/eshht` or `/holytrack` opens the options panel; `/eshht debug` prints auras on your target.

## Installation

1. Extract the folder `eSh_HolyTrack` into `E:\Games\Legion\Interface\AddOns\`.
2. The folder must contain:
   - `eSh_HolyTrack.toc`
   - `Core.lua`
   - `Libs\LibSharedMedia-3.0\` (embedded copy, no separate addon required)
3. Launch or reload the UI (`/reload`).

## Usage

### Options Panel
Open via:
- **Interface → Addons → eSh HolyTrack**
- or type `/eshht` (or `/holytrack`) in chat.

The panel contains:

| Section | Controls |
|---------|----------|
| **General** | Enable tracking, Locked (hide mover), Show pets |
| **Appearance** | Bar width (80‑600), Bar height (10‑30), Texture dropdown (LSM), Grow direction (Up/Down) |
| **Colours** | Per‑spell colour swatches in the watch list (opens WoW colour picker with alpha). |
| **Watch list** | Scrolling list of tracked spells. Each row shows: ☑ Enable • [Icon] • **ID \| Name** • Colour • **X** (delete) |
| **Add spell** | Enter a numeric spell ID and press **Add** – the addon fetches the name/icon and appends it to the watch list (default colour = orange). |
| **Profiles** | Dropdown to switch profiles, **Create** new profile from defaults, **Delete** current profile (cannot delete the last one). |
| **Reset position** | Returns the mover to the default spot (centered above your player frame). |

### Slash Commands
```
/eshht          – open options panel (same as /holytrack)
/holytrack      – same as above
/eshht debug    – print all buffs on your current target with spell ID, stacks, caster
```
(All other settings are managed in the options panel.)

### How it works
- The addon scans the player, party/raid, and (optionally) pet units every 0.15 s for auras whose spell ID or name matches an enabled entry in your profile's watch list.
- For each match it builds a list ordered by time remaining (Prayer of Mending also ordered by remaining charges).
- Bars are drawn from a fixed anchor (bottom when growing up, top when growing down) and grow inward as the aura expires.
- Permanent auras (e.g., Prayer of Mending when it shows no expiration) display as a full bar with `--` instead of a timer.

## Profiles
All settings (position, size, lock state, texture, grow direction, colours, enabled spells, pet flag, etc.) are saved per‑profile in `WTF\Account\<ACCOUNT>\<REALM>\<CHARACTER>\SavedVariables\eSh_HolyTrackDB.lua`.
Switching profiles changes the active set instantly; creating a new profile starts from the built‑in defaults.

## Custom Spells
To track any other HoT (e.g., Light of T'uure, Essence Font, etc.):
1. Find the spell ID (Wowhead, or hover‑cast it and run `/eshht debug` while targeting yourself).
2. In the Options panel → **Add spell by ID** → paste the ID → **Add**.
3. The spell appears in the watch list with a default colour; change the colour via the swatch, enable/disable with the checkbox, or delete with **X**.
4. The bar will show whenever that spell is present on a friendly unit (including yourself) and you cast it.

## Known Issues / Limitations
- Occasionally, when joining a raid mid‑combat, you may see `[ADDON_ACTION_BLOCKED]` related to `CompactRaidFrame`. This is a residual taint issue; the addon now pre‑creates all frames at login and blocks any frame creation during combat, which should eliminate it. If it persists, note the exact circumstances and report.
- The watch‑list UI does not validate that the entered ID actually corresponds to a heal‑over‑time spell; it will track any aura with that ID. This is intentional – you can track anything you like.
- LibSharedMedia‑3.0 is embedded; if another addon registers a texture with the same name, the latest registration wins (standard LSM behaviour).

## Changelog

**v1.2.1** – Embedded LibSharedMedia‑3.0, fixed raid‑duplicate buffs, added combat‑safe frame pool, watch‑list refresh on panel show, fixed PoM permanent‑aura display.

**v1.2.0** – Major redesign: watch‑list data model, LSM texture dropdown, scrollable spell UI, profiles, grow direction.

**v1.1.0** – Added Interface Options panel, lock/unlock, pets toggle, width/height sliders, colour pickers.

**v1.0.0** – Initial release: basic bar tracker for Renew and Prayer of Mending, movable/resizable frame.

## License
This addon is released into the public domain. Feel free to modify and redistribute.
