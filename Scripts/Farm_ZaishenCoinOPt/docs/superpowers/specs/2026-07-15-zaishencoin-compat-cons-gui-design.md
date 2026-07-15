# ZaishenCoin Compatibility, Consumables, and GUI Design

## Summary

This design updates the AutoIt ZaishenCoin farmer in three focused areas:

1. Remove the startup dependency on native AutoIt `Map()` support so the script launches on older AutoIt builds.
2. Add shared consumable logic and trigger it after every `Map_WaitMapLoading(..., 1)` call across shared travel, bounty scripts, and mission scripts.
3. Refresh the GUI so labels blend into the main window background while keeping the current dark theme and only a light futuristic accent.

## Goals

- Eliminate the launch error caused by unknown `Map()` / `MapExists()` functions.
- Use consumables automatically after explorable map loads only.
- Keep the consumable hook maintainable by centralizing the logic in one helper.
- Improve visual consistency without changing GUI layout or control behavior.

## Non-Goals

- No rewrite of quest-processing logic.
- No change to `Map_WaitMapLoading(..., 0)` behavior.
- No large GUI restructure, repositioning, or new controls.
- No broad refactor of mission or bounty flow beyond the targeted hook insertion.

## Code Changes

### 1. Compatibility fix

`ZaishenCoin.au3` currently attempts to use native AutoIt maps during lookup initialization. Older AutoIt builds fail before runtime fallback logic can help because the parser does not recognize `Map()` and `MapExists()`.

The implementation should:

- Remove direct usage of native `Map()` and `MapExists()`.
- Keep the existing array-backed lookup functions as the single code path.
- Preserve the existing quest ID membership behavior for bounty and mission checks.

Result:

- Startup no longer depends on AutoIt map support.
- Lookup behavior remains correct, with simple linear scans over the existing arrays.

### 2. Shared consumable logic

Add the following shared functions in common code:

- `IsCon($aItem)` using the provided model ID list.
- `UseCons()` using the provided bag scan and item use logic.

Add one new helper function for post-load behavior. The helper should:

1. `Sleep(1000)`
2. Check `Map_GetInstanceInfo("IsExplorable")`
3. If true, `Sleep(1000)` and call `UseCons()`

The helper should not perform the map load itself. It is called immediately after an existing `Map_WaitMapLoading(..., 1)` returns.

### 3. Consumable hook placement

Apply the helper after every `Map_WaitMapLoading(..., 1)` call in:

- `GwAu3_AddOns.au3`
- all bounty scripts under `Bounties\`
- all mission scripts under `Missions\`

Do not add the helper after:

- `Map_WaitMapLoading(..., 0)`
- any unrelated waits
- code paths that do not currently use `Map_WaitMapLoading`

This keeps the behavior tightly scoped to explorable-oriented load calls that already use `1` as the second parameter.

## GUI Design

`Gui.au3` already uses a dark card-based layout. The refresh should keep that structure but make label surfaces visually cleaner.

The implementation should:

- Make label backgrounds blend into the main window background.
- Keep panels for grouping and separation.
- Retain the existing dark theme and general spacing.
- Use restrained color tuning so the result feels slightly futuristic, not flashy.

Suggested treatment:

- Keep the window background as the dominant shared surface.
- Reduce panel contrast slightly so the GUI feels smoother.
- Keep accent colors muted and cool-toned.
- Preserve strong text contrast for readability.

Controls such as the log box, input, combo, and button may keep their control-specific styling where needed for usability.

## Data Flow

The relevant runtime flow after the change is:

1. A script calls `Map_WaitMapLoading($someMap, 1)`.
2. The call returns when the map load completes.
3. The new helper waits 1 second.
4. The helper checks whether the current instance is explorable.
5. If explorable, the helper waits another 1 second and calls `UseCons()`.

This makes consumable use conditional on the current instance type rather than on file location alone.

## Error Handling

- If an item pointer does not match `IsPcon()` or `IsCon()`, `UseCons()` skips it.
- If the current map is not explorable, the helper exits without using consumables.
- Existing mission and bounty logic remains unchanged aside from the new helper calls.

## Verification

Implementation should be checked with these focused validations:

- Script launches without the `Map()` unknown-function error.
- Search confirms every `Map_WaitMapLoading(..., 1)` site now has the helper directly after it.
- Search confirms `Map_WaitMapLoading(..., 0)` sites remain unchanged.
- GUI labels visually match the window background and remain readable.

## Risks

- Some runs may contain many `Map_WaitMapLoading(..., 1)` sites, so the patch touches many files.
- Repeated explorable transitions may use consumables more often than before by design.
- Minor GUI color changes could reduce contrast if tuned too aggressively, so readability must be checked after editing.
