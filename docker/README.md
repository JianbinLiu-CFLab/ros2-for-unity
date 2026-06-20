Ros2 For Unity Docker
===============

Docker is a Linux/Jazzy build and smoke candidate for this fork. It does not build Windows artifacts and it does not run Unity Editor.
Lyrical Docker evidence is not claimed until a Lyrical base image, .NET SDK package, and smoke run are validated.

Current status: Docker must pass the `r2fu-ci` command before it is treated as CI-candidate GREEN. Until then, Docker output is diagnostic evidence only.

## Fastest CI-candidate path

From the `docker/` directory:

```bash
. /opt/ros/jazzy/setup.bash
./build_image.sh
./run_container.sh r2fu-ci
```

The final command emits `R2FU_DOCKER_CI_SMOKE_PASS distro=jazzy platform=linux ...` when the Linux/Jazzy build, tests, and smoke checks pass.

## Build docker image

1. Optionally source ROS2:

```bash
. /opt/ros/<ROS_DISTRO>/setup.bash
```

If `ROS_DISTRO` is not set, `build_image.sh` defaults to `jazzy`.

2. Build image - image will be based on sourced ROS2 version or the Jazzy default:

```bash
./build_image.sh
```

Optional image name override:

```bash
R2FU_DOCKER_IMAGE=ros2-for-unity:jazzy-ci-candidate ./build_image.sh
```

Optional .NET SDK package override:

```bash
R2FU_DOTNET_SDK_PACKAGE=dotnet-sdk-8.0 ./build_image.sh
```

## Using docker container

1. Run docker container. Container should fetch the maintained branch you intend to build:

```bash
./run_container.sh
```

With no arguments, `run_container.sh` executes `r2fu-shell`, which prepares the workspace and then opens a shell.

2. Build asset. `./run_container.sh` script mounts `install` host directory inside docker, so you can find install results on host machine:

```bash
./run_container.sh r2fu-build
```

3. Run the CI-candidate command:

```bash
R2FU_DOCKER_IMAGE=ros2-for-unity:jazzy-ci-candidate \
R2FU_REF=main \
./run_container.sh r2fu-ci
```

`R2FU_REF` is checked out from `R2FU_REPO` inside the container. Use a branch or tag that already exists in that remote repository.

To validate a local checkout before pushing it, mount it explicitly:

```bash
R2FU_LOCAL_CHECKOUT=$(pwd)/.. ./run_container.sh r2fu-ci
```

When `R2FU_LOCAL_CHECKOUT` is set, the container copies that checkout into its workdir and skips the remote clone. This is the local-dev Docker validation path for unpushed commits and local-only branches.

`r2fu-ci` performs:

- repository checkout/import;
- standalone build with tests enabled;
- ros2cs test execution;
- artifact closure smoke through `r2fu-ci-smoke`.

The smoke checks required managed DLLs, managed assembly loadability, required Linux native libraries, minimum managed/native artifact counts, `ldd` closure for Linux native libraries, and basic ROS 2 CLI context availability.

Default smoke thresholds are `R2FU_DOCKER_MIN_MANAGED_FILES=10` and `R2FU_DOCKER_MIN_NATIVE_FILES=20`. Override them only when intentionally changing the artifact layout.
The ROS CLI smoke timeout defaults to `R2FU_DOCKER_ROS_CLI_TIMEOUT=30s`, which is intended to cover Fast DDS loopback discovery on cold CI runners.

## Validation signal matrix

| Signal | Platform | Distro | Proves | Does not prove |
|---|---|---|---|---|
| `R2FU_DOCKER_CI_SMOKE_PASS distro=jazzy platform=linux ...` | Linux container | Jazzy | Standalone build, ros2cs tests, managed DLL loadability, Linux native closure, and ROS CLI context | Windows artifact closure, Unity Editor import, Unity Play/Stop, Player smoke |
| Windows artifact rebuild scripts | Windows native | Jazzy | Windows package build/test/asset sanity when run separately | Linux Docker closure or Unity runtime behavior |
| Unity Load/Runtime/Player evidence | Windows Unity environment | Jazzy unless stated otherwise | Unity-side import and runtime behavior for the tested artifact | Docker/Linux readiness |

## Adding custom messages

You can add custom messages by putting them inside `docker/custom_messages` folder or just simply `git clone` them inside docker containers `/workdir/ros2-for-unity/src/ros2cs/src/custom_messages`

## Mounts and cache

`run_container.sh` mounts:

- `../install` to `/workdir/ros2-for-unity/install`
- `docker/custom_messages` to `/workdir/custom_messages`
- `docker/cache` to `/workdir/cache`
- `R2FU_LOCAL_CHECKOUT` to `/workdir/local-checkout` when that override is set

NuGet packages are cached under `docker/cache/nuget` through `NUGET_PACKAGES=/workdir/cache/nuget`. Remove that directory when you need a cold restore or want to reclaim disk space.

The container runs as the host uid/gid. Generated files should remain writable and removable by the host user.
