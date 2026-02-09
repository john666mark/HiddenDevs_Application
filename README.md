# HiddenDevs_Application

Overview:

The OreStation module manages a fully server‑side ore‑processing station.
It handles:

Placing and removing ore models

Generating and storing ore fragments

Updating player data via DataManager

Displaying dynamic UI (SurfaceGuis + BillboardGui)

Leveling and upgrading the station

Touch‑based fragment collection

Object pooling for performance‑optimized UI elements

The system is modular, scalable, and designed for high‑performance tycoon‑style gameplay.


NOTE1: The balancing between the Ore_StackAmount and the OreBulk (how many fragments you get per tick) needs to be redone.

NOTE2: Note on Internal Remake

This module is a simplified version of my current OreStation system.
I have already rebuilt the entire architecture into a clean server–client split, using:

a dedicated server class for all logic, data handling, and calculations

a client class responsible for UI replication and local effects

client‑side replication for BillboardGui animations to drastically reduce bandwidth usage

The original server‑only implementation caused heavy network load because the color‑sequence animations were replicated to all clients.
The new architecture solves this by running all visual effects locally.

However, I am not including the full remake here because HiddenDevs only accepts a single .luau file for submissions.
