# UIEssentials

A lightweight World of Warcraft addon providing "essential" (subjective, I know) UI enhancements. Built as a learning project to understand addon development while creating something useful for gameplay, everything I develop for this addon is used by myself as I love these features.

## Features

- **Tooltip Enhancement** - Shows unit targeting info with color-coded names by class/faction
- **Realm Name Removal** - Removes realm names from party/raid frames (keeps tooltips intact)
- **Item Level Decimals** - Displays precise item level in character frame
- **Cursor Highlight** - Optional green square to track cursor position
- **Item Comparison** - Restores Shift-to-compare behavior (disables auto-comparison)
- **Cooldown Color** - Colorizes action bar cooldown timers (Green: 1-8s, Yellow: 9-30s, Red: 30+s)

## Installation

1. Place `UIEssentials` folder in `World of Warcraft\_retail_\Interface\AddOns\`
2. Restart WoW or `/reload`

## Configuration

Access options via `/ue` or `/uiessentials`, or **ESC → Interface → AddOns → UIEssentials**. All features are enabled by default and can be toggled individually. Changes require `/reload`.

## Version

2.5

## Changelog

### 2.5 (26.01.2026)

- Add Cooldown Color module - colorizes cooldown timer text on action bars
- Green for 1-8 seconds, Yellow/Orange for 9-30 seconds, Red for 30+ seconds

### 2.4 (11.01.2026)

- Add Item Comparison control - disable auto-comparison and restore Shift-to-compare behavior
- Now respects the usual WoW behavior where holding Shift compares gear
