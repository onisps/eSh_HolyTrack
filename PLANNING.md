# eSh HolyTrack – Planning Docs

## Backlog (future ideas)

- [ ] Add aura filtering by unit role (tank/healer/dps) or by group (party only, raid only).
- [ ] Allow bar sorting options (time left, alphabetical, by spell ID).
- [ ] Export/import watch-list as a string (for sharing setups).
- [ ] Add sound alerts when a tracked aura falls below a threshold.
- [ ] Support for "stacks only" mode (show only charge count, no timer).
- [ ] Optional compact mode: hide names, show only icons + timers.
- [ ] Integration with ElvUI/AddOnSkins for automatic styling.
- [ ] Minimap icon to open options (LDB feed).
- [ ] Drag-and-drop reordering of watch-list rows.
- [ ] Optional bar grouping: all spells of one target on one row (like Grid).

## Issues (open)

| # | Description | Status |
|---|-------------|--------|
| 1 | Rare `[ADDON_ACTION_BLOCKED]` on `CompactRaidFrame` when joining raid mid-combat. Root cause was frame creation inside OnUpdate during combat; frames are now pre-created at login and creation is blocked in combat. | Mitigated; monitor for recurrence. |
| 2 | If LibSharedMedia-3.0 is also installed standalone, duplicate texture names may appear in the dropdown. | Cosmetic only. |
| 3 | "Add spell by ID" doesn't validate the spell is a HoT; it will track any aura with that ID. | By design. |
| 4 | Tooltip on bars may flicker when several targets have identical remaining time and the mouse moves between rows quickly. | Rare; acceptable. |
| 5 | WATCH: bars may not render for spells whose aura id differs from cast id until the spell name is fetched (needs a relogin after adding a brand-new id on some locales). | Under observation. |

## Decisions (key design choices)

| Decision | Reasoning |
|----------|-----------|
| Bar size as scale multipliers (0.25×–2×, step 0.01, base 200×18) | Same implementation as HandyNotes World Map Icon Scale: real size = base × scale, computed at render. Old absolute px values migrate to scale (width/200). |
| Embed LibSharedMedia-3.0 | Avoids requiring users to install a separate library; guarantees texture availability. |
| Watch-list driven scanning | Makes the addon generic – Renew and PoM are just two entries; users can add any spell without code changes. |
| Pre-create all frames at login | Eliminates secure taint (ADDON_ACTION_BLOCKED) caused by creating frames inside OnUpdate during combat. |
| Store everything per-profile | Allows players to have different setups for alts, specs, or encounters without manual reconfiguration. |
| Grow direction anchored to opposite edge | Bars grow from the anchor (bottom/top) inward; section labels sit just outside the block, keeping layout stable when direction flips. |
| Colour picker uses WoW's native ColorPickerFrame | No external dependencies; supports alpha and cancels correctly. |
| Spell ID + name matching for watch list | Handles cases where the aura on the target uses a different spell ID than the cast spell (e.g., Prayer of Mending aura ID 41637, or duration 0 permanent auras). |
| Visible mover only when unlocked | Provides clear visual feedback for repositioning while keeping the UI clean when locked. |
| Disable tracking via checkbox | Allows users to temporarily stop scanning without losing their watch list or settings. |
| Add spell by ID only | Prevents typos and locale issues; the spell name/icon is fetched from the client, guaranteeing correctness. |
| DBM-style bar layout (no frame chrome) | User preference: bars anchored at an edge growing inward, like DBM timers. |
| Custom scrollable dropdown for textures | UIDropDownMenu in 7.3.5 has no scroll support; a custom trigger+popup with UIPanelScrollFrameTemplate gives a real scrollbar and texture previews in every item. |
| Bars use flat WHITE8X8 texture by default | Clean look; any LSM texture can be selected. |
| Permanent auras show full bar with `--` | Prevents a bogus countdown on non-expiring auras like Prayer of Mending. |
| One row pool, fixed size (80 rows + 16 headers) | Simplifies logic and guarantees no combat-time allocation. |

## Todo (immediate)

- [ ] Test the fix for `[ADDON_ACTION_BLOCKED]` in a live raid encounter (join combat, watch for taint).
- [ ] Verify that the embedded LibSharedMedia works when the standalone `LibSharedMedia-3.0` addon is disabled or removed.
- [ ] Ensure profile switching updates the mover visibility correctly (lock state).
- [ ] Run a `/eshht debug` on a target with Prayer of Mending active to confirm the aura is detected and shows a full bar with `--`.
- [ ] Check that the colour swatches update instantly when a colour is changed via the picker.
- [ ] Confirm that the watch-list scroll frame resizes correctly when spells are added/removed.
- [ ] Verify that the watch list shows entries immediately when the Options panel is opened via Interface menu (OnShow hook).
- [ ] Verify duplicate-self fix: your own buffs should appear only once in raid and party.
- [ ] Consider adding a version bump and tagging v1.2.1 if using version control.
