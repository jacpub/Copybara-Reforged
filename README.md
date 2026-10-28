# Copybara Reforged

A development continuation of **Copybara**, the World of Warcraft chat-settings
copier originally created by **MickeyPickey**.

Copy chat tabs and settings between characters, or transfer them through the
existing `!COPYBARA:` import/export format.

## Development status

Version `1.1.2-reforged-dev.1` is an in-development preview targeting Retail
12.1.5. Local validation passes on Lua 5.1.5: 372 mocked API/input cases, 24 real
bundled-codec cases, and 45 Lua syntax checks. These checks do not establish
in-game, combat, taint, options-widget or persistence compatibility. Classic
client files retain their historical interface declarations and are unverified.

The continuation adds modern metadata/chat API handling, ordered channel
restoration, validation before chat mutations, safe empty/malformed import
rejection, stale-profile handling and checks on imported parent relationships.

## Folder and saved settings

The addon folder remains **`Copybara`** and account-wide saved data remains
**`CopybaraDB`**. The global name `Copybara` and export prefix `!COPYBARA:` are
preserved. Do not rename the installed folder to `Copybara Reforged`.

Use one `Copybara` installation at a time. Back up the existing chat configuration
and `WTF/Account/<account>/SavedVariables/Copybara.lua` before testing an update.
The addon saves the current character's chat settings at logout. In the addon
options, select a previously saved source character and apply its settings, or
export/import the existing transfer string. Successful apply reloads the UI.

## Local tests

From the repository root, with Lua 5.1 available:

```sh
lua tests/copybara_bridge_mock.lua Copybara/Copybara.lua
```

The real-codec test uses the preserved original 1.1.2-release comparison fixture:

```sh
lua tests/copybara_codec_roundtrip.lua . tests/fixtures/Copybara-1.1.2-original.lua
```

The mocked suite covers modern/legacy API selection, profile identity, channel
tuples, rejection before mutation and parent/cycle handling. The codec suite uses
the bundled LibSerialize and LibDeflate with synthetic data; chat application is
intercepted. The existing inflater has no bounded-output-memory guarantee.

## Credits and provenance

Original addon: [MickeyPickey/Copybara](https://github.com/MickeyPickey/Copybara),
[CurseForge project 715273](https://www.curseforge.com/wow/addons/copybara).
The supplied baseline is `1.1.2-release`, dated September 6, 2023. This project
is a continuation and does not claim to be the original author's release.

Original author metadata, logo provenance and embedded-library notices are
retained. See [NOTICE.txt](NOTICE.txt) and each dependency's source/license text.
No blanket replacement license is applied to inherited material.
