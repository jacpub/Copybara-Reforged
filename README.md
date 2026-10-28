# Copybara Reforged

![Copybara Reforged banner with a capybara scribe writing by candlelight](assets/copybara-reforged-banner.webp)

Copybara Reforged copies saved chat tabs and settings between World of Warcraft characters. It continues the original Copybara addon by MickeyPickey.

You can transfer settings through the addon or use its `!COPYBARA:` import/export text format. The settings include chat window names, layout, dimensions, position, docking, font size, colors, transparency, interactability, message groups, and channel selections.

## Install

1. Back up your existing chat configuration and `WTF/Account/<account>/SavedVariables/Copybara.lua` before replacing or testing an installation.
2. Open the [repository](https://github.com/jacpub/Copybara-Reforged) on GitHub and choose Code > Download ZIP.
3. Extract the ZIP. Copy only the nested `Copybara` directory into `Interface/AddOns`. The installed path should be `Interface/AddOns/Copybara/Copybara.toc`.
4. Keep the addon folder named `Copybara`, and use only one `Copybara` installation at a time. The saved data uses `CopybaraDB`.

## Use

1. On the character whose settings you want to copy, log out with the addon enabled. The addon saves that character's current chat settings at logout.
2. On the target character, open Settings > AddOns > Copybara Reforged and select the saved source character.
3. Choose Apply. Applying a valid configuration changes the chat settings and reloads the UI.
4. To transfer settings as text, use Export for the selected source and Import on the other character. Importing a valid configuration also changes the chat settings and reloads the UI.

## Development status

A tester reported Export rejecting a saved profile with "Invalid fields in chat window 1." This preview adds the rejected field, Lua type, and reason to that message so the cause can be identified. Invalid settings remain rejected.

The project targets World of Warcraft Retail and Forever. Version `1.1.2-reforged-dev.2` is a development preview targeting Retail 12.1.5; Forever compatibility has not been verified. Offline checks do not establish compatibility in-game, in combat, with taint, with options widgets, or with logout/reload persistence.

## Developer details

<details>
<summary>Local checks and technical notes</summary>

From the repository root, with Lua 5.1 available:

```sh
lua tests/copybara_bridge_mock.lua Copybara/Copybara.lua tests/fixtures/Copybara-reforged-dev1.lua
```

The real-codec test uses the preserved original 1.1.2-release comparison fixture:

```sh
lua tests/copybara_codec_roundtrip.lua . tests/fixtures/Copybara-1.1.2-original.lua
```

Offline validation covers 648 mocked API/input cases, 24 real bundled-codec cases, and 47 Lua syntax checks, including the preserved comparison fixtures. The mocked suite covers modern/legacy API selection, profile identity, channel tuples, rejection before mutation, parent/cycle handling, and privacy-safe field diagnostics. The codec suite uses the bundled LibSerialize and LibDeflate with synthetic data; chat application is intercepted. The existing inflater has no bounded-output-memory guarantee.

</details>

## Credits and provenance

Original addon: [MickeyPickey/Copybara](https://github.com/MickeyPickey/Copybara), [CurseForge project 715273](https://www.curseforge.com/wow/addons/copybara). The supplied baseline is `1.1.2-release`, dated September 6, 2023. This project continues that addon and is not a release by the original author.

Original author metadata, logo provenance, and embedded-library notices are retained. See [NOTICE.txt](NOTICE.txt) and each dependency's source/license text. No blanket replacement license is applied to inherited material.
