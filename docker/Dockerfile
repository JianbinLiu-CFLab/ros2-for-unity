# syntax=docker/dockerfile:1.4
## Modifications Copyright (c) 2026 Jianbin Liu.
##
## Modifications by Jianbin Liu:
## - Defaulted the container toolchain to Jazzy/.NET 10 to match ros2cs tests.
## - Removed stale apt caches after package installs to keep the image smaller.
## - Added CI-candidate command helpers and reduced broad filesystem permissions.
## - Installed Ninja because the R2FU build scripts explicitly select that generator.
## - Installed the tf2 benchmark CMake dependency required by source builds with tests.

ARG ROS2_DISTRO=jazzy
FROM ros:${ROS2_DISTRO}-ros-base
# .NET 10 matches the current ros2cs test target; core/common remain netstandard2.0 for Unity compatibility.
ARG DOTNET_SDK_PACKAGE=dotnet-sdk-10.0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV R2FU_WORKDIR=/workdir/ros2-for-unity
ENV NUGET_PACKAGES=/workdir/cache/nuget

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ninja-build \
    patchelf \
    rsync \
    ${DOTNET_SDK_PACKAGE} \
    ros-${ROS_DISTRO}-ament-cmake-google-benchmark \
    ros-${ROS_DISTRO}-test-msgs \
    ros-${ROS_DISTRO}-fastrtps \
    ros-${ROS_DISTRO}-rmw-fastrtps-cpp \
    ros-${ROS_DISTRO}-cyclonedds \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    && curl -s https://packagecloud.io/install/repositories/dirk-thomas/vcstool/script.deb.sh | bash \
    && apt-get install -y --no-install-recommends python3-vcstool

COPY entrypoint.sh /entrypoint.sh
COPY ci_smoke.sh /usr/local/bin/r2fu-ci-smoke
RUN chmod +x /entrypoint.sh /usr/local/bin/r2fu-ci-smoke

# /workdir must be writable for arbitrary host uid/gid mappings used by run_container.sh.
# Use a sticky world-writable work root instead of recursively chmodding /home.
RUN mkdir -p /workdir/ros2-for-unity /workdir/cache/nuget /workdir/custom_messages \
    && chmod 1777 /workdir /workdir/ros2-for-unity /workdir/cache /workdir/cache/nuget /workdir/custom_messages

ENTRYPOINT [ "/entrypoint.sh" ]
