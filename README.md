![GitHub commit activity](https://img.shields.io/github/commit-activity/m/titaniummachine1/lmaobox-Navbot-Medbot)  
![GitHub Release Date](https://img.shields.io/github/release-date/titaniummachine1/lmaobox-Navbot-Medbot)  
![GitHub all releases](https://img.shields.io/github/downloads/titaniummachine1/lmaobox-Navbot-Medbot/total)

# LMAOBox-Navbot

**A dynamic pathfinding and navigation bot for Team Fortress 2, powered by LMAOBox Lua.**

> **Note:** This script **requires** [lnxLib](https://github.com/lnx00/Lmaobox-Library/releases/latest). Ensure it’s installed before running NavBot.

---

## Quickstart Guide

1. **Download** the latest [Lmaobot.lua](https://github.com/titaniummachine1/lmaobox-Navbot-Medbot/releases) and place it in `%localappdata%`.
2. **Generate nav meshes**: If you don't have nav meshes, run `MakeNavs.bat` from the source code.
3. **Start TF2**, inject LMAOBox, and play on a **CTF**, **PL**, or **PLR** map.
4. Open the **Lua** tab in LMAOBox and load `Lmaobot.lua`.

And that's it—NavBot is ready to guide you through TF2!

---

## Developer Instructions

### Building from source:
1. **Install Node.js** from [here](https://nodejs.org/).
2. **Download** and extract the [source code](https://github.com/titaniummachine1/lmaobox-Navbot-Medbot/releases).
3. Run the following commands in the **Node.js command prompt**:
    ```bash
    npm install luabundle
    ```
4. Execute `Bundle.bat` and then `BundleAndDeploy.bat`.
5. Finally, run `MakeNavs.bat` to generate nav meshes for all supported maps.

---

### License
This project is open-source and free to use.