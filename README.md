# Bodkin Storage
### Automated Storage and Crafting using ComputerCraft (CCTweaked) and Plethora.



## Background

I wanted to challenge myself by creating a program capable of inventory management. The program would track where certain items were stored, and store, retrieve and craft items on command.

In the game Minecraft, one of the main mechanics is [crafting](https://minecraft.gamepedia.com/Crafting). Crafting works by having an interface with a 3x3 grid to place materials in, and an output where the result will be. Different combinations of items in the grid will result in different results. For example, crafting a wooden pickaxe requires placing the following items in this formation:

![Crafting a wooden pickaxe](docs/woodenPickCraft.png)

In an unmodified copy of the game, there are close to 400 items. Keeping track of these items manually can be a task. However I was using a modified version that added many more items to the game, making inventory management into more of a chore than a fun gameplay element.

One of the modifications I am using is called [CCTweaked](https://www.curseforge.com/minecraft/mc-mods/cc-tweaked) which is a fork of a popular mod adding simple programmable computers to the game which can interact with the world around them using LUA. Using this and an [additional](https://squiddev-cc.github.io/plethora/) mod that adds more functionality to the computers, I am able to program them to move items between chests in the world.
