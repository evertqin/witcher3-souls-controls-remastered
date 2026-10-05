# Dark Souls Controls and Controller Diagram — Current + Alt1

Version: 1.1.0  
Prepared: October 4, 2026  
Target: The Witcher 3: Wild Hunt — Remastered, Windows PC v5.00c (Steam)  
Input format: Version=60

This package offers two controller schemes and a pre-game launcher. Each choice
applies its bindings and matching Settings > Controls diagram before starting
the game. The schemes differ only in mounted riding controls.

## Choose a scheme

1. Extract the entire archive to a folder you can write to. Keep the launcher,
   control-schemes folder, and compatibility.json together.
2. Fully close The Witcher 3.
3. Double-click **Start-Witcher3.cmd**.
4. Choose **1 — Current** or **2 — Alt1**. Enter keeps the previous selection;
   0 cancels without changing any files.
5. The launcher applies the selected bindings and diagram, backs up the previous
   active files, and starts the game through Steam.

Use this launcher whenever you want the choice before starting. Starting the
game directly from Steam uses whichever scheme was last applied.

The launcher detects Steam libraries and your Windows Documents folder,
including OneDrive redirection. If it cannot find the game, use Steam's
Manage > Browse local files and paste that folder when prompted.

No administrator privileges are normally needed. If your game folder requires
them, run the launcher with an account that can write to the game's mods folder.
The CMD wrapper runs this local PowerShell script without changing your global
PowerShell execution policy.

## Mounted riding comparison

L3 means pressing the left stick. A means Xbox A / PlayStation Cross.

| Action | Current | Alt1 |
| --- | --- | --- |
| Canter | Hold A | Hold L3 |
| Gallop | Double-press A, holding the second press | Double-press L3, holding the second press |
| Horse follow | A | L3 |
| Available mounted object interactions | Press L3 | Press A |

Alt1 moves the mounted Container, GatherHerbs, FastTravel, and Use actions to A.
The game still controls which objects can be used while riding. Native gesture
timings are preserved: Alt1 is a button remap, not a speed-toggle mod.

Both Geralt and Ciri receive the L3 speed bindings in Alt1. Ciri's mounted
interaction availability follows the native game; this mod does not enable
interactions that are unavailable to her. The mounted diagram is marked
**(Current)** or **(Alt1)** and shows the selected speed and interaction buttons.

## Shared controls

| Button | Geralt action |
| --- | --- |
| RB / R1 | Light attack; hold for an unlocked special light attack |
| RT / R2 | Heavy attack; hold for an unlocked special heavy attack |
| LB / L1 | Guard/counter in combat; Witcher Senses while exploring |
| LT / L2 | Selected item/crossbow; hold to aim where supported |
| X / Square | Cast selected Sign with Standard Sign Casting |
| Y / Triangle | Radial menu |
| B / Circle | Dodge in combat; jump while exploring |
| A / Cross | Roll in combat; interact while exploring; native sprint behavior |

On-foot, boat, swimming, combat, keyboard/mouse, and Photo Mode bindings are the
same in both schemes. Scripted riding's Gallop action also moves to L3 in Alt1.
Movement, camera, target lock, equipment selection, and other native options are
preserved. The supplied keyboard/mouse bindings use a QWERTY baseline.

Use **Gameplay > Standard Sign Casting** for X/Square to cast the selected Sign
directly. Quick Sign Casting changes the Sign button into a modifier for native
action combinations and has not been independently tested with this layout.

## Files and installation locations

The launcher installs these two files together:

- `control-schemes/<scheme>/input.settings` goes into your actual Windows
  `Documents/The Witcher 3/input.settings`.
- `control-schemes/<scheme>/modDarkSoulsControllerScheme/content/scripts/game/gui/main_menu/ingamemenu/igmUtilities.ws`
  goes into `<game folder>/mods/modDarkSoulsControllerScheme/content/scripts/game/gui/main_menu/ingamemenu/igmUtilities.ws`.

These are different destinations. Do not copy the entire extracted archive into
your game or Documents folder. Use the launcher, or copy the two selected scheme
files manually while the game is closed. Never install both diagram variants
under different mod names at the same time.

Each scheme replaces the complete input.settings file, including keyboard
bindings. Any later personal key edits are preserved in a backup when you switch
but are not automatically merged into the stored scheme snapshots. The launcher
checks the supplied snapshots for integrity; changing a snapshot requires
updating its corresponding hashes in compatibility.json.

## Backups and recovery

Before each switch, the launcher saves existing active files under:

`Documents/The Witcher 3/control-scheme-backups/<timestamp>/`

- `input.settings`: previous active bindings, if present.
- `igmUtilities.ws`: previous active controller diagram script, if present.

If a switch fails after changing one file, the launcher attempts to restore the
previous files and does not start the game. Close the game before restoring a
backup manually. Copy the binding backup to Documents and the diagram backup to
the mod script's game-folder location shown above.

Launcher preferences are saved beside the launcher as launcher-settings.json.
This remembers the chosen scheme and game location; deleting that file resets
the launcher preferences.

## Compatibility and scope

Built against Windows PC Remastered v5.00c and the Version=60 input format.
The launcher refuses an incompatible input format or changed vanilla controller
UI script rather than installing an old script over a different game build.
Other versions, consoles, and other PC storefronts have not been verified.

Keep local mods enabled in the game. Other mods that replace igmUtilities.ws need
a script merge. The launcher installs the supplied diagram file, so it will
replace a manually merged version at that same path after making a backup.
Other mods that edit input.settings need a careful manual merge.

The diagram uses the game's original localized labels and existing controller
artwork. Tutorial illustrations/text are outside this package's scope.

## Troubleshooting

- Game already running: fully exit it before switching. The launcher will refuse
  changes while witcher3 is running.
- Wrong mounted buttons: start using the launcher and select the intended
  scheme; inspect the Current/Alt1 label on the mounted controller diagram.
- Default diagram: enable local mods and verify the mod script location above.
- Different input format or UI script: update the package for your game build.
- Missing/changed scheme payload: extract an intact package again.
- Read-only or locked destination: close the game/editor and remove read-only
  from the destination file if you previously set it.
- Windows Documents detection needs an override: use -DocumentsPath with the
  full path to the actual The Witcher 3 settings folder.

## Command-line use

Open PowerShell in the extracted package folder:

```powershell
# Apply Alt1 and start the game through Steam:
.\Choose-Controls.ps1 -Scheme Alt1

# Restore Current without starting the game:
.\Choose-Controls.ps1 -Scheme Current -ApplyOnly

# Override locations when automatic detection is unavailable:
.\Choose-Controls.ps1 -Scheme Alt1 -GamePath 'D:\Games\The Witcher 3' -DocumentsPath 'D:\Documents\The Witcher 3' -ApplyOnly
```

The CMD wrapper also accepts these arguments. Interactive selection is the
default when -Scheme is omitted.

## Uninstall

1. Close the game.
2. Restore your pre-install input.settings backup into the actual Windows
   Documents/The Witcher 3 folder.
3. Remove only `<game folder>/mods/modDarkSoulsControllerScheme`, or restore any
   diagram script backup that existed before installation.
4. Remove the extracted launcher/package folder if no longer needed.

To return to the original custom scheme instead of uninstalling, choose Current
in the launcher. Both schemes retain the shared Souls-style combat bindings.

## Validation

- Current bindings were saved unchanged from the active settings file.
- Alt1 changes only 12 controller binding lines in four riding-related contexts.
  All 48 input sections, keyboard bindings, action names, and timings remain.
- Diagram changes are limited to the two mounted Geralt/Ciri diagram blocks.
- Tested under Windows PowerShell 5.1 using isolated game/settings fixtures:
  applying each scheme, matching diagram installation, exact backups, rollback
  after a locked diagram, temporary-file cleanup, and refusal for a running game,
  incompatible input/UI format, or changed scheme payload.
- The original custom bindings survived a game rewrite. Alt1 riding behavior and
  the updated diagram appearance still require in-game testing.

## Credits

CD PROJEKT RED: The Witcher 3 and original controller UI script/localization.
Shared controller layout adapted from the supplied legacy Dark Souls-style input
preset and merged into the Remastered input format.

## Development and release builds

Requires Windows and Windows PowerShell 5.1 or newer. Verification uses isolated
temporary fixtures and does not alter your installed game or active bindings.

```powershell
# Check scheme application, backups, rollback, and compatibility guards:
.\verification\Test-ControlsLauncher.ps1

# Create and verify the Nexus upload ZIP in dist/:
.\Build-Release.ps1
```

The release contains the README, launcher, compatibility manifest, and both
schemes. Test fixtures and build tooling stay in the source repository.
The repository preserves original file bytes to keep the payload hashes valid.
