# Territect
Territect is a Lua script for The Powder Toy which dynamically generates random terrain using user-defined presets. These can be used for building saves (as long as it is a preset save or the terrain is not the focus of the save), but the script is largely intended for personal use.

# Features
Current version:
* Versatile terrain engine with multi-pass generation
* Built-in editor that allows users to design custom presets
* Embed presets into saves and then publish them to share with others
* Preset management system for storing, saving, and loading presets in folders
* Generate layers of material with random local variations in thickness
* Generate randomly-placed veins of material to simulate ores or other random formations
* Temporarily make solids affected by gravity

Future versions:
* Additional generation modes (flatten, etc.)
* Ability to control properties of generated particles (temp, deco, life, etc.) within a specified random range
* More horizontal control over terrain features (distribution of veins, cliffs, hills, etc.)
* Finer control over shape of veins (round instead of diamond, random edges, etc.)
* Solidify non-solid materials temporarily
* Remember veins/particles placed previous layer
* Modifiers based on previous layer (encase, scatter, etc.)
* Vein clusters (place new veins based on relative position of old veins)
* Control pass draw action (optionally overwrite)
