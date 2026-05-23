# ROS2 For Unity - Windows 10/11

This readme contains information specific to Windows. For general information, please see [README.md](README.md).

Current local maintenance evidence targets Windows 10 LTSC + ROS 2 Jazzy. Windows 11 is expected to use the same toolchain, but should be verified separately before making release claims.

## Current toolchain policy

- Use ROS 2 Jazzy through the maintained environment wrapper when running ROS/colcon commands in this workspace.
- Use Ninja as the Windows generator for Jazzy builds. This is the preferred ROS 2 Windows build shape and avoids unsupported Visual Studio generator detection with newer Visual Studio shells.
- If Visual Studio 2026 / `VSCMD_VER=18.*` is present, do not rely on colcon auto-detecting a Visual Studio generator. Pass `-G Ninja` or set the generator through the wrapper/build orchestrator.
- If CMake finds the wrong Python, pass `"-DPython3_EXECUTABLE:FILEPATH=<jazzy-pixi-python>"` as one quoted `-D` argument.
- ROS 2 Jazzy + FastRTPS may print `ERRORFailed to load RTI Connext DDS Micro` while probing installed RMW plugins. Treat it as non-blocking only when `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`, build/test exit codes are 0, and the message appears only in ROS interface package stderr.

## Building

The historical instructions below assume `C:\dev` and older ROS 2 layouts. For this fork's Jazzy maintenance line, prefer the repository-local scripts and the short-path build bases documented under `D:\ros2unity\plan`.

Do not run `colcon build` directly against this repository's `src` directory when `src\ros2cs` is a junction to a canonical ros2cs checkout. On Windows, Python packages such as `sensor_msgs_py` can compute junction-relative `egg_base` paths incorrectly and fail even though the canonical ros2cs workspace is buildable. Use `build.ps1`, which resolves the canonical ros2cs checkout and builds from that source path.

### Prerequisites

It is necessary to complete the `ros2cs` Windows prerequisites for the same branch/fork used by this repository. For this maintenance line, `ros2cs.repos` points to the maintained `JianbinLiu-CFLab/ros2cs` `main` branch.

### Steps

* Make sure [long paths on Windows are enabled](https://github.com/RobotecAI/ros2cs/blob/master/README-WINDOWS.md#important-notices)
* Make sure you open a Visual Studio Developer PowerShell compatible with the installed ROS 2 Jazzy toolchain.
* Prefer Ninja generator builds on Windows. Newer Visual Studio generator names may not be supported by the Jazzy-pinned CMake/colcon stack.
* Clone this project.
  ```powershell
  git clone git@github.com:JianbinLiu-CFLab/ros2-for-unity.git C:\dev\ros2-for-unity
  ```
* Source your ROS2 installation in the terminal before you proceed.
  ```
  C:\dev\ros2_jazzy\local_setup.ps1
  ```
* Enter `Ros2ForUnity` working directory.
    ```powershell
    cd C:\dev\ros2-for-unity
    ```
* Set up you custom messages in `ros2_for_unity_custom_messages.repos`
* Import necessary and custom messages repositories.
    ```powershell
    .\pull_repositories.ps1
    ```
    > *NOTE* `pull_repositories.ps1` script doesn't update already existing repositories, you have to remove `src\ros2cs` folder to re-import new versions.
* Build `Ros2ForUnty`. You can build it in standalone or overlay mode.
    ```powershell
    # standalone mode
    ./build.ps1 -standalone
    
    # overlay mode
    ./build.ps1
    ```
  * You can build with `-clean_install` to make sure your installation directory is cleaned before deploying.
* Unity Asset is ready to import into your Unity project. You can find it in `install/asset/` directory.
* (optionally) To create `.unitypackage` in `install/unity_package`
  ```powershell
  create_unity_package.ps1
  ```
  > *NOTE* Please provide path to your Unity executable when prompted. Unity license is required. In case your Unity license has expired, the `create_unity_package.ps1` won't throw any errors but `Ros2ForUnity.unitypackage` won't be generated too.

## Build troubleshooting

- If you see one of the following errors:
><script_name> is not digitally signed

><script_name> cannot be loaded because running scripts is disabled on this system

Please execute `Set-ExecutionPolicy Bypass -Scope Process` in PS shell session to enable third party scripts execution only for this session. Otherwise please refer to official [Execution Policies](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.1).

- If you see the following error:
>     [4.437s] Traceback (most recent call last):
>     [4.437s]   File "<string>", line 1, in <module>
>     [4.437s]   File "C:\Python38\lib\site-packages\numpy\__init__.py", line 148, in <module>
>     [4.437s]     from . import _distributor_init
>     [4.437s]   File "C:\Python38\lib\site-packages\numpy\_distributor_init.py", line 26, in <module>
>     [4.437s]     WinDLL(os.path.abspath(filename))
>     [4.437s]   File "C:\Python38\lib\ctypes\__init__.py", line 373, in __init__
>     [4.453s]     self._handle = _dlopen(self._name, mode)
>     [4.453s] OSError: [WinError 193] %1 is not a valid Win32 application
>     [4.469s] CMake Error at C:/dev/ros2_foxy/share/rosidl_generator_py/cmake/rosidl_generator_py_generate_interfaces.cmake:213 (message)
>     [4.469s]   execute_process(C:/Python38/python.exe -c 'import
>     [4.469s]   numpy;print(numpy.get_include())') returned error code 1
>     [4.469s] Call Stack (most recent call first):
>     [4.469s]   C:/dev/ros2_foxy/share/ament_cmake_core/cmake/core/ament_execute_extensions.cmake:48 (include)
>     [4.469s]   C:/dev/ros2_foxy/share/rosidl_cmake/cmake/rosidl_generate_interfaces.cmake:286 (ament_execute_extensions)
>     [4.484s]   CMakeLists.txt:16 (rosidl_generate_interfaces)
Please reinstall `numpy` package from python by typing:
```powershell
pip uninstall numpy
pip install numpy
```

**If no solution of your problem is present in the section above, please make sure to check out `ros2cs` [Troubleshooting section](https://github.com/RobotecAI/ros2cs/blob/master/README-WINDOWS.md#troubleshooting)**

## OS-Specific usage remarks

> If the Asset is built with `-standalone` flag (the default), then nothing extra needs to be done.
Otherwise, you have to source your ros distribution before launching either Unity3D Editor or Application.

> Note that after you build the Asset, you can use it on a machine that has no ros2 installation (if built with `-standalone`).

> You can simply copy over the `Ros2ForUnity` subdirectory to update your Asset.
