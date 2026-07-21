<!--
Modifications Copyright (c) 2026 Jianbin Liu.
Modifications by Jianbin Liu:
- Updated Windows guidance for the JianbinLiu-CFLab Jazzy maintenance line, short-path build policy, artifact evidence, and forked ros2cs troubleshooting links.
- Documented the supported ROS 2 Lyrical Windows runtime and artifact line.
- Documented the ROS 2 Humble Windows standalone artifact line and its validation boundary.
-->

# ROS2 For Unity - Windows 10/11

This readme contains information specific to Windows. For general information, please see [README.md](README.md).

Current local artifact evidence covers ROS 2 Humble, Jazzy, and Lyrical Windows standalone packages. The deepest recorded Unity-facing validation remains the Windows 10 LTSC Jazzy/Lyrical path; Windows 11 should be verified separately before making release claims.

## Current Windows validation snapshot

The current Humble artifact validation snapshot is:

```text
ROS 2:     Humble
RMW:       rmw_fastrtps_cpp
R2FU:      v0.8.1
ros2cs:    v0.8.1
Artifact:  Ros2ForUnity_humble_standalone_windows_x86_64.zip
Release:   v0.8.1
SHA256:    see the release .sha256.txt asset
Scope:     build/package closure; Unity Load and Runtime Smoke not yet revalidated
```

The current local Jazzy validation snapshot is:

```text
OS:        Windows 10 LTSC
ROS 2:     Jazzy
RMW:       rmw_fastrtps_cpp
Unity:     6000.3.14f1
R2FU:      v0.8.1
ros2cs:    v0.8.1
Artifact:  Ros2ForUnity_jazzy_standalone_windows_x86_64.zip
Release:   v0.8.1
SHA256:    see the release .sha256.txt asset
```

The current local Lyrical validation snapshot is:

```text
OS:        Windows 10 LTSC
ROS 2:     Lyrical
RMW:       rmw_fastrtps_cpp
Unity:     6000.3.14f1
R2FU:      v0.8.1
ros2cs:    v0.8.1
Artifact:  Ros2ForUnity_lyrical_standalone_windows_x86_64.zip
Release:   v0.8.1
SHA256:    see the release .sha256.txt asset
```

Current source release after the latest cleanup fixes:

```text
R2FU:      v0.8.1
ros2cs:    v0.8.1
Release:   v0.8.1
Artifact:  Humble, Jazzy, and Lyrical zips uploaded with matching .sha256.txt and .manifest.json release assets
```

Validated gates:

- Windows-native standalone build through `build.ps1` for Humble, Jazzy, and Lyrical.
- Standalone artifact packaging for Humble, Jazzy, and Lyrical.
- `ros2cs_tests` passes as part of the Windows full-validation ladders for both Jazzy and Lyrical.

Not yet validated by this snapshot:

- Broad Unity Load smoke across every supported Unity/Windows combination.
- Broad runtime pub/sub or service/client smoke beyond the recorded Jazzy/Lyrical artifact paths.
- Broad ROS graph discovery stability across every RMW and wait-set mode.
- Sensor runtime behavior outside the recorded Unity/Lyrical acceptance path.
- Unity Player export beyond recorded local validation paths.
- Windows 11.

## Current toolchain policy

- Use ROS 2 Humble, Jazzy, or Lyrical through the maintained environment wrappers when running ROS/colcon commands in this workspace.
- Use Ninja as the Windows generator for Jazzy builds. This is the preferred ROS 2 Windows build shape and avoids unsupported Visual Studio generator detection with newer Visual Studio shells.
- If Visual Studio 2026 / `VSCMD_VER=18.*` is present, do not rely on colcon auto-detecting a Visual Studio generator. Pass `-G Ninja` or set the generator through the wrapper/build orchestrator.
- If CMake finds the wrong Python, pass `"-DPython3_EXECUTABLE:FILEPATH=<jazzy-pixi-python>"` as one quoted `-D` argument.
- ROS 2 Jazzy + FastRTPS may print `ERRORFailed to load RTI Connext DDS Micro` while probing installed RMW plugins. Treat it as non-blocking only when `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`, build/test exit codes are 0, and the message appears only in ROS interface package stderr.
- Lyrical standalone runtime uses the ros2cs direct spin fallback unless `ROS2CS_SPIN_FALLBACK` is overridden. Treat wait-set-specific claims separately from the supported artifact/runtime path.

## Building

The historical instructions below assume `C:\dev` and older ROS 2 layouts. For this fork's Jazzy maintenance line, prefer the repository-local scripts. The Windows build wrapper uses short build/log roots by default; override them with `R2FU_ROS2CS_BUILD_BASE` and `R2FU_ROS2CS_LOG_BASE` when you need explicit paths.

Do not run `colcon build` directly against this repository's `src` directory when `src\ros2cs` is a junction to a canonical ros2cs checkout. On Windows, Python packages such as `sensor_msgs_py` can compute junction-relative `egg_base` paths incorrectly and fail even though the canonical ros2cs workspace is buildable. Use `build.ps1`, which resolves the canonical ros2cs checkout and builds from that source path.

### Prerequisites

It is necessary to complete the `ros2cs` Windows prerequisites for the same branch/fork used by this repository. For this maintenance line, `ros2cs.repos` points to the maintained `JianbinLiu-CFLab/ros2cs` commit hash recorded in that file. The `main` branch remains the active integration line, but public builds should use pinned inputs.

### Steps

* Make sure [long paths on Windows are enabled](https://github.com/JianbinLiu-CFLab/ros2cs/blob/main/README-WINDOWS.md#important-notices)
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
  * You can build with `-clean_install` to remove the R2FU install tree plus the configured ros2cs build, log, and install roots before deploying.
  * Build scripts print a phase timing summary covering metadata generation, ros2cs build, Unity asset staging, plugin deploy, and metadata copy.
  * Use `-quiet` to reduce live colcon terminal output while keeping logs under the configured colcon log base. Use `-console_direct` to preserve the chatty `console_direct+` output.
  * `build.ps1` warns when the local `src\ros2cs` checkout does not match `ros2cs.repos`; pass `-strict_pin` to make the mismatch fail the build.
  * Windows standalone deployment validates required managed and native closure files after copy, including `ros2cs_common.dll`, `ros2cs_core.dll`, `rcl.dll`, `class_loader.dll`, `fastdds*.dll`, `rmw_implementation.dll`, `rcl_logging_implementation.dll`, `rosidl_buffer_backend_registry.dll`, and the required ament index entries.
* Unity Asset is ready to import into your Unity project. You can find it in `install/asset/` directory.
* (optionally) To create `.unitypackage` in `install/unity_package`
  ```powershell
  .\create_unity_package.ps1 -unity_path <your-path-to-unity-editor-executable>
  ```
  > *NOTE* Unity license is required. The script removes stale package output before export, verifies that Unity produced a non-empty package, and writes a matching `.sha256.txt` next to the `.unitypackage`. By default the package filename includes the current ROS distro and `windows_x86_64`, for example `Ros2ForUnity_jazzy_windows_x86_64.unitypackage`.

## Unity Load smoke

For the local maintenance workspace, the reusable Unity Load smoke project is:

```text
D:\ros2unity\R2FUUnityLoadSmoke
```

It is intentionally outside this git repository. It validates import/compile/native-load/`ROS2UnityCore` initialization only. It does not validate runtime pub/sub, graph discovery, sensors, Player export, or Product GREEN.

Run it with a standalone-clean environment:

```powershell
$unity = 'C:\Program Files\Unity\Hub\Editor\6000.3.14f1\Editor\Unity.exe'
$project = 'D:\ros2unity\R2FUUnityLoadSmoke'
$log = 'D:\ros2unity\logs\r2fu-unity-load-smoke.log'
$env:ROS_DISTRO = $null
$env:ROS_VERSION = $null
$env:ROS_PYTHON_VERSION = $null
$env:AMENT_PREFIX_PATH = $null
$env:COLCON_PREFIX_PATH = $null
$env:RMW_IMPLEMENTATION = $null
& $unity -projectPath $project -batchmode -nographics -quit -executeMethod R2FUUnityLoadSmoke.Run -logFile $log
```

Pass marker:

```text
R2FU_UNITY_LOAD_SMOKE_PASS
```

## Build troubleshooting

- If a standalone build is unexpectedly slow during native DLL copy or artifact staging, check antivirus/Defender real-time scanning first. This repository does not change Defender policy automatically; any exclusions should be a deliberate local or CI-machine decision.

- If `pull_repositories.ps1` exits non-zero, fix the reported network, authentication, or existing `src\ros2cs` checkout problem before building. The script does not update an existing checkout in place; remove or move `src\ros2cs` when you intentionally want to re-import the pinned repositories.

- If `build.ps1` exits non-zero, do not package the existing `install\asset` output as a fresh artifact. Re-run the failed command after fixing the reported error, or use `-clean_install` to remove stale staged asset files and ros2cs build/install outputs before rebuilding.

- If packaging creates no `.unitypackage` or zip artifact, treat the artifact as missing. Re-run package creation after confirming `install\asset\Ros2ForUnity` exists and came from a successful build.

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

**If no solution of your problem is present in the section above, please make sure to check out this fork's `ros2cs` [Troubleshooting section](https://github.com/JianbinLiu-CFLab/ros2cs/blob/main/README-WINDOWS.md#troubleshooting). RobotecAI upstream documentation is useful historical reference, but this fork's Jazzy Windows toolchain may differ.**

## OS-Specific usage remarks

> If the Asset is built with `-standalone` flag (the default), then nothing extra needs to be done.
Otherwise, you have to source your ros distribution before launching either Unity3D Editor or Application.

> Note that after you build the Asset, you can use it on a machine that has no ros2 installation (if built with `-standalone`).

> You can simply copy over the `Ros2ForUnity` subdirectory to update your Asset.
