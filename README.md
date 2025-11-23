# Target ToolTip

A World of Warcraft addon that enhances unit tooltips with targeting information. Initially built over one week as a learning project to understand how addons work. After years of playing WoW, I figured "why not" create my own. Learning Lua while building something for a game I play so much made the process much more engaging. I've also aimed to keep it lightweight and performant as far as I could understand at this point in time.

## Features

### Tooltip Enhancement

- Shows what a unit is currently targeting
- Displays which party/raid members are targeting them
- Color-coded names by class and faction for quick recognition

### Realm Name Removal

- Automatically removes realm names from party frames
- Automatically removes realm names from raid frames
- Keeps your UI clean when playing with cross-realm players, without removing realm on tooltips.

## Installation

1. Download or clone this repository
2. Place the `TargetToolTip` folder in your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart WoW or reload UI (`/reload`)

## Usage

Simply hover over any unit to see the enhanced tooltip with targeting information. No configuration needed - realm name removal is automatically enabled.

## Version

1.1.0

## Changelog

### 1.1.0 (23.11.2025)

- Added realm name removal for party and raid frames
- Merged functionality from RemoveRealmNames addon

### 1.0.0 (22.11.2025)

- Initial release with tooltip targeting information
