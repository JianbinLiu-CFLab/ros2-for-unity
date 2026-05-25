## Modifications Copyright (c) 2026 Jianbin Liu.
##
## Modifications by Jianbin Liu:
## - Defaulted the container toolchain to Jazzy/.NET 8.
## - Removed stale apt caches after package installs to keep the image smaller.

ARG ROS2_DISTRO=jazzy
FROM ros:${ROS2_DISTRO}-ros-base

RUN apt update && apt install -y ros-${ROS_DISTRO}-test-msgs ros-${ROS_DISTRO}-fastrtps ros-${ROS_DISTRO}-rmw-fastrtps-cpp ros-${ROS_DISTRO}-cyclonedds ros-${ROS_DISTRO}-rmw-cyclonedds-cpp && rm -rf /var/lib/apt/lists/*

RUN apt update && apt install -y curl wget git && rm -rf /var/lib/apt/lists/*

RUN curl -s https://packagecloud.io/install/repositories/dirk-thomas/vcstool/script.deb.sh | sudo bash
RUN apt update && apt install -y python3-vcstool && rm -rf /var/lib/apt/lists/*

RUN apt update && apt install -y apt-transport-https patchelf dotnet-sdk-8.0 && rm -rf /var/lib/apt/lists/*
RUN apt update && apt install -y ffmpeg libsm6 libxext6 libgtk-3-0 && rm -rf /var/lib/apt/lists/*

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /workdir/ros2-for-unity
RUN chmod -R 777 /workdir
RUN chmod -R 777 /home

ENTRYPOINT [ "/entrypoint.sh" ]
