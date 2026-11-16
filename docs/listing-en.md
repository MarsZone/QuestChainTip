# Store listing (English)

> Paste the Summary / Description blocks into CurseForge, Wago, or a GitHub release.

## Name

Quest Chain Tip

## Summary (under 200 chars)

Questie enriches quests you can accept. This adds the same for quests you already have: description, rewards and the whole follow-up chain. Hover on the world map, hold Shift for the full chain window.

## Description

**The gap it fills**

Questie shows description, rewards and the follow-up chain only for quests you have *not* accepted yet.
Once a quest is in your log, hovering it gives you objectives and nothing else — you cannot tell how many
steps remain, what they reward, or whether the chain sends you into a dungeon.

Quest Chain Tip fills that gap for every quest: available, in progress, and completed.

**Hover panel on the world map**

- Quest description (configurable line count)
- Rewards: XP, money, items (quality coloured), reputation
- Follow-up chain (configurable depth, default 3)
- Prerequisites

Shown only on world map quest markers by default; can be set to "off" or "everywhere".
It never shows on the minimap, never in the chat frame (so Shift-click quest linking still works),
and never in the quest log — Shift-click there stays the native "link to chat" behaviour.

**Hold Shift on the world map for the chain window**

One card per quest in the chain:

- Objectives
- Rewards — XP, money, items. Items are quality coloured, hover for the item tooltip, click to open
- Quest description text
- Where to accept / hand in (NPC name + zone)
- Dungeon / raid / elite flag
- State: available / in progress / completed

Completed quests are collapsed by default; one button in the top-right expands everything.
The window is draggable and scrollable, `Esc` closes it.

**Notes**

- Requires Questie and QuestieDB (they ship the quest database; this addon does not redistribute it)
- Client: WoW Classic "Forever" / Era, Interface 16001
- Nothing is appended to the system tooltip — everything is drawn on its own frame, so there is no flicker
- Item rewards also work for quests you have not accepted: the addon scans the QuestieDB item table
  (`questRewards`) once per session and builds a reverse quest → item index

**Commands**

`/qct` settings · `/qct depth 5` · `/qct detail` · `/qct explain` (chat diagnostics, off by default) · `/qct why` and `/qct log` (attach these when reporting a problem)

**Localisation**

Quest names, NPC names and item names follow your client locale via Questie. The addon's own labels
are currently Chinese only; an English UI pass is planned.

## Tags

quests, quest chain, questie, classic, addon, rewards

## Category

Quests

## Screenshots

1. Hover a world map quest marker — description + rewards + follow-up chain panel
2. Shift chain window (dungeon flag, accept / hand-in locations)
3. Item tooltip on hover inside the window
4. Options panel
5. Before / after: the same accepted quest in Questie vs. with this addon
