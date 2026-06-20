<!--
Modifications Copyright (c) 2026 Jianbin Liu.
Modifications by Jianbin Liu:
- Reframed Ubuntu instructions as legacy guidance for the current Jazzy maintenance line and pointed ros2cs prerequisites to the maintained fork.
-->

# ROS2 For Unity - Ubuntu 20.04, 22.04, and 24.04

This readme contains information specific to Ubuntu 20.04/22.04/24.04. For general information, please see [README.md](README.md)

> Current status: these Ubuntu instructions are retained as legacy guidance. This Jazzy maintenance line has not recently revalidated Ubuntu 20.04/22.04/24.04. Treat the commands below as a starting point until a fresh Ubuntu build/test record is added.
>
> The current Build GREEN / Unity Load GREEN evidence is Windows-native only. Do not infer Ubuntu support from the Windows Jazzy artifact or Unity Load smoke result.

## Building

We assume that working directory is `~/ros2-for-unity` and we are using a sourced ROS 2 installation. Older examples mention Galactic/Foxy; the current active maintenance target is Jazzy.

### Prerequisites

Start with installation of dependencies. Make sure to complete each step of this fork's `ros2cs` [Prerequisites section](https://github.com/JianbinLiu-CFLab/ros2cs/blob/main/README-UBUNTU.md#prerequisites). RobotecAI upstream documentation is useful historical reference, but this fork's Jazzy toolchain may differ.

### Steps

* Clone this project.
    ```bash
    git clone git@github.com:JianbinLiu-CFLab/ros2-for-unity.git ~/ros2-for-unity
    ```
* You need to source your ROS2 installation before you proceed, for each new open terminal. It is convenient to include this command in your `~/.profile` file.
    ```bash
    # jazzy
    . /opt/ros/jazzy/setup.bash
    ```
* Enter `Ros2ForUnity` working directory.
    ```bash
    cd ~/ros2-for-unity
    ```
* Set up you custom messages in `ros2_for_unity_custom_messages.repos`
* Import necessary and custom messages repositories.
    ```bash
    ./pull_repositories.sh
    ```
    > *NOTE* `pull_repositories.sh` script doesn't update already existing repositories, you have to remove `src/ros2cs` folder to re-import new versions.
* Build `Ros2ForUnty`. You can build it in standalone or overlay mode.
    ```bash
    # standalone mode
    ./build.sh --standalone
    
    # overlay mode
    ./build.sh
    ```
    * You can add `--clean-install` to remove the R2FU install tree plus the ros2cs build, log, and install roots before deploying.
    * `build.sh` warns when the local `src/ros2cs` checkout does not match `ros2cs.repos`; pass `--strict-pin` to make the mismatch fail the build.
    * Linux standalone deployment validates required managed and native closure files after copy, including `ros2cs_common.dll`, `ros2cs_core.dll`, `librcl.so*`, `libclass_loader.so*`, `libfastdds.so*`, `librmw_implementation.so*`, `librcl_logging_implementation.so*`, `librosidl_buffer_backend_registry.so*`, and the required ament index entries.
* Unity Asset is ready to import into your Unity project. You can find it in `install/asset/` directory.
* (optionally) To create `.unitypackage` in `install/unity_package`
    ```bash
    ./create_unity_package.sh -u <your-path-to-unity-editor-executable>
    ```
    > *NOTE* Unity license is required. The script removes stale package output before export, verifies that Unity produced a non-empty package, and writes a matching `.sha256.txt` next to the `.unitypackage`. By default the package filename includes the current ROS distro and `linux_x86_64`, for example `Ros2ForUnity_jazzy_linux_x86_64.unitypackage`.

## OS-Specific usage remarks

You can run Unity Editor or App executable from GUI (clicking) or from terminal as long as ROS2 is sourced in your environment.
The best way to ensure that system-wide is to add `source /opt/ros/jazzy/setup.bash` to your `~/.profile` file.
Note that you need to re-log for changes in `~/.profile` to take place.
Running Unity Editor through Unity Hub is also supported.

## Build troubleshooting

These Ubuntu instructions are retained as legacy guidance for the current Jazzy maintenance line.

* If `pull_repositories.sh` exits non-zero, fix the reported network, authentication, or existing `src/ros2cs` checkout problem before building. The script does not update an existing checkout in place; remove or move `src/ros2cs` when you intentionally want to re-import the pinned repositories.

* If `build.sh` exits non-zero, do not package or copy the existing `install/asset` output as a fresh artifact. Re-run the failed command after fixing the reported error, or use `--clean-install` to remove stale staged asset files and ros2cs build/install outputs before rebuilding.

* If package creation produces no `.unitypackage`, treat the artifact as missing and re-run package creation only after confirming `install/asset/Ros2ForUnity` came from a successful build.

## Usage troubleshooting

**No ROS environment sourced. You need to source your ROS2 (..)**

* If you see `"No ROS environment sourced. You need to source your ROS2 (..)"` message in Unity3D Editor, it means your environment was not sourced properly. This could happen if you run Unity but it redirects to Hub and ignores your console environment variables (this behavior can depend on Unity3D version). In such case, run project directly with `-projectPath` or add ros2 sourcing to your `~/.profile` file (you need to re-log for it to take effect).

* Keep in mind that `UnityHub` stays in the background after its first launch and Unity Editor launch without `-projectPath` will redirect to it and the Hub will start Unity Editor. Since environment variables for the process are set on launch and inherited by child processes, your sourced ros2 environment in the console launching the Editor this way won't be applied. To make sure it applies (and to change between different ros2 distributions), make sure to terminate existing UnityHub process and run it with the correct ros2 distribution sourced.

**There are no errors but I can't see topics published by Ros2ForUnity**

* Make sure your dds config is correct.
* Sometimes ROS2 daemon brakes up when changing network interfaces or ROS2 version. Try to stop it forcefully (`pkill -9 _ros2_daemon`) and restart (`ros2 daemon start`).
