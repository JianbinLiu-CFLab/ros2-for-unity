Ros2 For Unity Docker
===============

Docker is a Linux/Jazzy build and smoke candidate for this fork. It does not build Windows artifacts and it does not run Unity Editor.

Current status: Docker must pass the `r2fu-ci` command before it is treated as CI-candidate GREEN. Until then, Docker output is diagnostic evidence only.

## Fastest CI-candidate path

From the `docker/` directory:

```bash
. /opt/ros/jazzy/setup.bash
./build_image.sh
./run_container.sh r2fu-ci
```

The final command emits `R2FU_DOCKER_CI_SMOKE_PASS` when the build, tests, and smoke checks pass.

## Build docker image

1. Source ROS2:

```bash
. /opt/ros/<ROS_DISTRO>/setup.bash
```

2. Build image - image will be based on sourced ROS2 version:

```bash
./build_image.sh
```

Optional image name override:

```bash
R2FU_DOCKER_IMAGE=ros2-for-unity:jazzy-ci-candidate ./build_image.sh
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

`R2FU_REF` is checked out from `R2FU_REPO` inside the container. Use a branch or tag that already exists in that remote repository; local-only branches are not visible to the container.

`r2fu-ci` performs:

- repository checkout/import;
- standalone build with tests enabled;
- ros2cs test execution;
- artifact closure smoke through `r2fu-ci-smoke`.

The smoke checks required managed DLLs, required Linux native libraries, `ldd` closure for `librcl`, and basic ROS 2 CLI context availability.

## Adding custom messages

You can add custom messages by putting them inside `docker/custom_messages` folder or just simply `git clone` them inside docker containers `/workdir/ros2-for-unity/src/ros2cs/src/custom_messages`

## Mounts and cache

`run_container.sh` mounts:

- `../install` to `/workdir/ros2-for-unity/install`
- `docker/custom_messages` to `/workdir/custom_messages`
- `docker/cache` to `/workdir/cache`

NuGet packages are cached under `docker/cache/nuget` through `NUGET_PACKAGES=/workdir/cache/nuget`. Remove that directory when you need a cold restore or want to reclaim disk space.

The container runs as the host uid/gid. Generated files should remain writable and removable by the host user.
