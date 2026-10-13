# Research Safe Deconstruction

**Author:** FlexWares Gaming

This addon marks items in the ESO smithing and universal deconstruction lists:

- A green circular marker means every included crafter either knows the item's trait or is currently researching it.
- A red circular marker means at least one included crafter does not know the trait, or the addon has no recorded research data for that character.
- A yellow circular marker identifies only the excess research copies when there are more compatible items in the deconstruction list than the included characters still need. The lowest-quality copies are reserved and remain red when possible. This is enabled by default and can be disabled in Settings.
- Items without a researchable trait are marked green because deconstructing them cannot consume a trait research opportunity, except for ornate and intricate items, which are left unmarked.

The addon uses `LibCharacterKnowledge`, so log in to every crafter at least once after installing it. Characters are included by default on the current megaserver. In the addon's Settings UI, use the **Monitored characters** checkboxes to add or remove characters from the safety checks. Use these commands to manage them as well:

```text
/rsd list
/rsd toggle <character number or name>
/rsd all
```

Research completion updates the markers automatically, but characters remain monitored until you uncheck them in Settings or toggle them with `/rsd`.
Overflow markers reserve one copy for each included character that still needs the trait and only use complete research data; missing data keeps an item unsafe.

The marker is research safety only. It does not decide whether an item is valuable, locked, part of an uncollected set, or otherwise worth keeping. Ornate and intricate items are intentionally left unmarked.

Markers use the transparent, bright ESO hammer icon, so the deconstruction dialog's existing background remains visible while only the marker color changes. Markers are refreshed when research or inventory state changes and before a deconstruction page is shown.
