# Copyright 2019-2022 Robotec.ai.
# Modifications Copyright (c) 2026 Jianbin Liu.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import xml.etree.ElementTree as ET
import subprocess
import pathlib
import os
import io

SCRIPT_DIR = pathlib.Path(__file__).parent
R2FU_ROOT = SCRIPT_DIR.parents[1]
R2FU_ASSET = SCRIPT_DIR.parent.joinpath("Ros2ForUnity")
ROS2CS_PATH = SCRIPT_DIR.parent.joinpath("ros2cs")

def get_git_commit_and_date(working_directory) -> tuple[str, str]:
    output = run_git(['log', '-1', '--format=%H%n%ci'], working_directory)
    sha, date = output.split('\n', 1)
    return sha.strip(), date.strip()

def get_git_description(working_directory) -> str:
    return run_git(['describe', '--tags', '--always'], working_directory)

def get_git_abbrev(working_directory) -> str:
    return run_git(['rev-parse', '--abbrev-ref', 'HEAD'], working_directory)

def run_git(args, working_directory) -> str:
    try:
        return subprocess.check_output(
            ['git'] + args,
            cwd=working_directory,
            stderr=subprocess.STDOUT,
        ).decode('utf-8', errors='replace').strip()
    except subprocess.CalledProcessError as exc:
        output = exc.output.decode('utf-8', errors='replace').strip()
        raise RuntimeError(f"git {' '.join(args)} failed in {working_directory}: {output}") from exc

def get_ros2_for_unity_root_path() -> pathlib.Path:
    # metadata_generator.py is expected to live under <repo>/src/scripts.
    return R2FU_ROOT

def get_ros2_for_unity_path() -> pathlib.Path:
    # metadata_generator.py is expected to live under <repo>/src/scripts.
    return R2FU_ASSET

def get_ros2_version() -> str:
    return os.environ.get("ROS_DISTRO", "unknown")

def require_existing_path(path: pathlib.Path, description: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"{description} not found: {path}")

def require_directory(path: pathlib.Path, description: str) -> None:
    if not path.is_dir():
        raise FileNotFoundError(f"{description} not found: {path}")

def get_runtime_plugin_files(plugins_dir: pathlib.Path) -> list[str]:
    runtime_files = []
    for path in plugins_dir.rglob("*"):
        if not path.is_file():
            continue
        name = path.name
        if name.endswith(".dll") or name.endswith(".so") or ".so." in name:
            runtime_files.append(path.relative_to(plugins_dir).as_posix())
    return sorted(runtime_files)

def add_plugin_inventory(root: ET.Element, plugins_dir: pathlib.Path | None) -> None:
    if plugins_dir is None:
        return

    runtime_files = get_runtime_plugin_files(plugins_dir)
    plugins = ET.SubElement(root, "plugins")
    plugins.set("root", str(plugins_dir))
    plugins.set("runtime_file_count", str(len(runtime_files)))
    for runtime_file in runtime_files:
        ET.SubElement(plugins, "file").text = runtime_file

def main() -> None:
    parser = argparse.ArgumentParser(description='Generate metadata file for ros2-for-unity.')
    parser.add_argument('--standalone', action='store_true', help='is a standalone build')
    parser.add_argument('--ros2cs-path', default=str(ROS2CS_PATH), help='path to the ros2cs checkout')
    parser.add_argument('--plugins-dir', default=None, help='optional Ros2ForUnity Plugins directory to inventory')
    args = parser.parse_args()

    ros2_for_unity_root_path = get_ros2_for_unity_root_path()
    ros2_for_unity_path = get_ros2_for_unity_path()
    ros2cs_path = pathlib.Path(args.ros2cs_path).resolve(strict=False)
    plugins_dir = pathlib.Path(args.plugins_dir).resolve(strict=False) if args.plugins_dir else None
    ros2_version = get_ros2_version()

    require_existing_path(ros2_for_unity_root_path.joinpath(".git"), "ros2-for-unity .git")
    print(f"Using ros2cs checkout: {ros2cs_path}")
    require_directory(ros2cs_path, "ros2cs checkout")
    require_existing_path(ros2cs_path.joinpath(".git"), "ros2cs .git")
    require_directory(ros2_for_unity_path, "Ros2ForUnity asset directory")
    if plugins_dir is not None:
        require_directory(plugins_dir, "Ros2ForUnity Plugins directory")

    ros2_for_unity_sha, ros2_for_unity_date = get_git_commit_and_date(ros2_for_unity_root_path)
    ros2cs_sha, ros2cs_date = get_git_commit_and_date(ros2cs_path)

    ros2_for_unity = ET.Element("ros2_for_unity")
    ET.SubElement(ros2_for_unity, "ros2").text = ros2_version
    ros2_for_unity_version = ET.SubElement(ros2_for_unity, "version")
    ET.SubElement(ros2_for_unity_version, "sha").text = ros2_for_unity_sha
    ET.SubElement(ros2_for_unity_version, "desc").text = get_git_description(ros2_for_unity_root_path)
    ET.SubElement(ros2_for_unity_version, "date").text = ros2_for_unity_date
    ET.SubElement(ros2_for_unity_version, "branch").text = get_git_abbrev(ros2_for_unity_root_path)

    ros2_cs = ET.Element("ros2cs")
    ET.SubElement(ros2_cs, "ros2").text = ros2_version
    ros2_cs_version = ET.SubElement(ros2_cs, "version")
    ET.SubElement(ros2_cs_version, "sha").text = ros2cs_sha
    ET.SubElement(ros2_cs_version, "desc").text = get_git_description(ros2cs_path)
    ET.SubElement(ros2_cs_version, "date").text = ros2cs_date
    ET.SubElement(ros2_cs_version, "branch").text = get_git_abbrev(ros2cs_path)
    ET.SubElement(ros2_cs, "standalone").text = str(int(args.standalone))
    add_plugin_inventory(ros2_cs, plugins_dir)

    metadata_rf2u_file = ros2_for_unity_path.joinpath("metadata_ros2_for_unity.xml")
    write_metadata_xml(ros2_for_unity, metadata_rf2u_file)

    metadata_r2cs_file = ros2_for_unity_path.joinpath("metadata_ros2cs.xml")
    write_metadata_xml(ros2_cs, metadata_r2cs_file)

def write_metadata_xml(root: ET.Element, destination: pathlib.Path) -> None:
    # ET.indent requires Python 3.9+; ROS 2 Jazzy's supported Python satisfies this.
    ET.indent(root, space="   ")
    buffer = io.BytesIO()
    ET.ElementTree(root).write(buffer, encoding="utf-8", xml_declaration=True)
    new_content = buffer.getvalue()
    if destination.exists() and destination.read_bytes() == new_content:
        return

    temporary_destination = destination.with_name(destination.name + ".tmp")
    try:
        temporary_destination.write_bytes(new_content)
        os.replace(temporary_destination, destination)
    finally:
        if temporary_destination.exists():
            temporary_destination.unlink()

if __name__ == "__main__":
    main()
