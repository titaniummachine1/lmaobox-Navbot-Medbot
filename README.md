## This script **REQUIRES** [lnxLib](https://github.com/lnx00/Lmaobox-Library/releases/latest/). It will NOT work without this lua.

# LMAOBox-Navbot
Pathfinding and navigation bot made with LMAOBox Lua.

Support: https://dsc.gg/rosnehook

Credits for original code: Inx00

# How to use LMAOBox-Navbot

First, go to releases and download the Lmaobot.lua script to your ``%localappdata%`` folder.

If you don't have nav meshes (if you don't know what I'm talking about, you don't have them,) you need to download MakeNavs.bat from the source code and run it.

Start TF2, inject LMAOBox, and go into a CTF, PL, or PLR map (currently only supporting these)

Go to the Lua tab in the menu and load "Lmaobot.lua"

Enjoy NavBot on LMAOBox!

# How to compile/bundle (dev only)
First, go to https://nodejs.org/ and download and install the stable version of Node.JS

Next, go to releases and download the source code (zip) and unzip it to any place you want.

After that, you open the **Node.JS command prompt** and execute
```
npm install luabundle
```

Once it has installed, run Bundle.bat and after it finishes run BundleAndDeploy.bat

When those batch scripts have finished, run MakeNavs.bat to get nav meshes for all causal maps

Start TF2, inject LMAOBox (not beta build), and go into a map.

Go to the Lua tab in the menu and load "Lmaobot.lua"

Enjoy NavBot on LMAOBox!
