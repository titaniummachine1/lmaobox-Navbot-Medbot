@echo off

set /p tf_map_path="Please enter the path to your tf/maps folder (example: C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\maps): "

move /Y "navmeshes\*" "%tf_map_path%"

pause