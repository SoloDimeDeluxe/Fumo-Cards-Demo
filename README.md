# Fumo Cards Demo

A Roblox (Luau) prototype of an **ability card system** inspired by *Fumo Horrors*, built as a scripting portfolio piece. Everything is greyboxed on purpose: the focus is the code, not the art.

## What's implemented

| Card | Type | Behaviour (from the game's wiki) |
|---|---|---|
| **Spirit Power Sample Bottle** | Active | No killer within 15 studs → **Scan**: white silhouette on every killer, friendly and player (15s cooldown). Killer within 15 studs → **Burst**: flings every killer within 20 studs (60s cooldown). |
| **Physical Enhancement Jizo** | Passive | +75 max HP and double HP regen while standing still. Doesn't stack with other health cards. |
| **Law of the Survival of the Fittest** | Passive | Lets you keep sprinting while exhausted, at the cost of HP. That damage is affected by "damage taken" multipliers. |

Supporting systems:

- **Stamina & sprint**, server-authoritative (the client only sends "I want to sprint").
- **Custom health regen** that cards can modify (replaces Roblox's default `Health` script).
- **Killer AI**: chases the closest player, uses `PathfindingService` only when line of sight is blocked.
- **Contact damage** from killers, disabled while they're stunned by the Burst.
- **HUD**: health bar with damage trail, stamina bar, equipped cards row with tooltips, card cast animation and cooldown countdown.
- **Input** through `ContextActionService`: keyboard, gamepad and on-screen touch buttons.

## Architecture

```
src/server/
├── CardSystem/
│   ├── CardService.server.lua    -- loads cards, equips them, combines modifiers, runs active cards
│   ├── StatsService.server.lua   -- stamina, sprint and health regen, driven by player attributes
│   ├── Damage.lua                -- single damage pipeline (applies DamageTakenMultiplier)
│   └── Cards/                    -- one ModuleScript per card, mostly pure data
├── EnemyChase.server.lua         -- killer movement + pathfinding
└── KillerDamage.server.lua       -- contact damage
src/client/                       -- input, HUD and visual effects
src/character/Health.server.lua   -- empty on purpose, disables default regen
```

Key ideas:

- **Cards are data.** A passive card only declares `Modifiers` (e.g. `MaxHealthBonus = 75`). `CardService` merges every equipped card using per-modifier rules (`Highest`, `Any`) and publishes the result as player attributes. `StatsService` reads those attributes and never needs to know which card provided them.
- **Active cards return their result.** `Activate(context)` performs the gameplay effect on the server and returns `{ Cooldown, ClientEffects }`. `CardService` handles validation, cooldowns and replication generically, and wraps the call in `pcall` so one broken card can't take down the system.
- **The server owns gameplay state.** Cooldowns, stamina and damage are all decided server-side; clients only send intents.

### Adding a new card

Create a ModuleScript in `src/server/CardSystem/Cards/`:

```lua
-- Passive example
return {
	DisplayName = "My Card",
	Type = "Passive",
	ImageId = "rbxassetid://...",
	Modifiers = { MaxHealthBonus = 25 },
}
```

```lua
-- Active example
local MyCard = { DisplayName = "My Active", Type = "Active", ImageId = "rbxassetid://..." }

function MyCard.Activate(context)
	-- context.Player, context.Character, context.Root
	return { Cooldown = 10 }
end

return MyCard
```

No other file needs to change (a brand-new modifier type only needs a rule in `MODIFIER_RULES` and a consumer that reads its attribute).

## Controls

| Action | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Sprint (hold) | Left Shift | Left stick click | "Correr" button |
| Use active card | E | X | "Carta" button |
| Toggle test cards | 1 / 2 / 3 | — | — |
| Toggle killers aggressive mode | K | — | — |

## Running it

Recreate the `src` structure in Studio and paste each file's contents. The file suffix tells you the script type:

| File | Studio object | Goes in |
|---|---|---|
| `*.server.lua` | Script | `src/server` → ServerScriptService, `src/character` → StarterPlayer › StarterCharacterScripts |
| `*.client.lua` | LocalScript | `src/client` → StarterPlayer › StarterPlayerScripts |
| `*.lua` | ModuleScript | same folder as above (e.g. `CardSystem/Cards`) |

The test map lives in the place file (not in this repo). It needs, in `Workspace`:

- `Enemies` folder with a few **unanchored** 4×4×4 Parts (the killers).
- `Friendlies` folder with a few anchored Parts (optional, revealed by the Scan).
- Some anchored walls to test pathfinding and the through-wall silhouettes.

## Notes

- Card art is referenced by asset ID and is not included in this repository. *Fumo Horrors* and its card designs belong to their respective creators; this is an unofficial fan-made prototype.
- Values marked as "tuning" in the code (sprint speed, stamina drain, fling strength…) are not on the wiki and are placeholders.
