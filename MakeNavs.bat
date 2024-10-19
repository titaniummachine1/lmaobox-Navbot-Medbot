@echo off

set /p tf_map_path="Please enter the path to your tf/maps folder (example: \Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\maps) or press return (enter) to use the example path: "

if "%tf_map_path%"=="" (
 echo "Using default"
 move /Y "navmeshes\*" "\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\tf\maps"
 pause
 exit
)

move /Y "navmeshes\*" "%tf_map_path%"

pause
