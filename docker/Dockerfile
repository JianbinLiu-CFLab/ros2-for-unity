## Modifications Copyright (c) 2026 Jianbin Liu.
##
## Modifications by Jianbin Liu:
## - Defaulted the container toolchain to Jazzy/.NET 8.
## - Removed stale apt caches after package installs to keep the image smaller.
## - Added CI-candidate command helpers and reduced broad filesystem permissions.

ARG ROS2_DISTRO=jazzy
FROM ros:${ROS2_DISTRO}-ros-base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV R2FU_WORKDIR=/workdir/ros2-for-unity

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    apt-transport-https \
    patchelf \
    dotnet-sdk-8.0 \
    ffmpeg \
    libsm6 \
    libxext6 \
    libgtk-3-0 \
    ros-${ROS_DISTRO}-test-msgs \
    ros-${ROS_DISTRO}-fastrtps \
    ros-${ROS_DISTRO}-rmw-fastrtps-cpp \
    ros-${ROS_DISTRO}-cyclonedds \
    ros-${ROS_DISTRO}-rmw-cyclonedds-cpp \
    && rm -rf /var/lib/apt/lists/*

RUN curl -s https://packagecloud.io/install/repositories/dirk-thomas/vcstool/script.deb.sh | bash \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3-vcstool \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY ci_smoke.sh /usr/local/bin/r2fu-ci-smoke
RUN chmod +x /entrypoint.sh /usr/local/bin/r2fu-ci-smoke

# /workdir must be writable for arbitrary host uid/gid mappings used by run_container.sh.
# Use a sticky world-writable work root instead of recursively chmodding /home.
RUN mkdir -p /workdir/ros2-for-unity /workdir/cache /workdir/custom_messages \
    && chmod 1777 /workdir /workdir/ros2-for-unity /workdir/cache /workdir/custom_messages

ENTRYPOINT [ "/entrypoint.sh" ]
