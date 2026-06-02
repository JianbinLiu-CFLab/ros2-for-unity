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

def get_git_commit(working_directory) -> str:
    return run_git(['rev-parse', 'HEAD'], working_directory)

def get_git_description(working_directory) -> str:
    return run_git(['describe', '--tags', '--always'], working_directory)

def get_commit_date(working_directory) -> str:
    return run_git(['show', '-s', '--format=%ci'], working_directory)

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
    return pathlib.Path(__file__).parents[2]

def get_ros2_for_unity_path() -> pathlib.Path:
    # metadata_generator.py is expected to live under <repo>/src/scripts.
    return pathlib.Path(__file__).parents[1].joinpath("Ros2ForUnity")

def get_ros2cs_path() -> pathlib.Path:
    # ros2cs is expected beside Ros2ForUnity under <repo>/src.
    return pathlib.Path(__file__).parents[1].joinpath("ros2cs")

def get_ros2_version() -> str:
    return os.environ.get("ROS_DISTRO", "unknown")

def require_existing_path(path: pathlib.Path, description: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"{description} not found: {path}")

def require_directory(path: pathlib.Path, description: str) -> None:
    if not path.is_dir():
        raise FileNotFoundError(f"{description} not found: {path}")

def main() -> None:
    parser = argparse.ArgumentParser(description='Generate metadata file for ros2-for-unity.')
    parser.add_argument('--standalone', action='store_true', help='is a standalone build')
    args = parser.parse_args()

    require_existing_path(get_ros2_for_unity_root_path().joinpath(".git"), "ros2-for-unity .git")
    require_directory(get_ros2cs_path(), "ros2cs checkout")
    require_existing_path(get_ros2cs_path().joinpath(".git"), "ros2cs .git")
    require_directory(get_ros2_for_unity_path(), "Ros2ForUnity asset directory")

    ros2_for_unity = ET.Element("ros2_for_unity")
    ET.SubElement(ros2_for_unity, "ros2").text = get_ros2_version()
    ros2_for_unity_version = ET.SubElement(ros2_for_unity, "version")
    ET.SubElement(ros2_for_unity_version, "sha").text = get_git_commit(get_ros2_for_unity_root_path())
    ET.SubElement(ros2_for_unity_version, "desc").text = get_git_description(get_ros2_for_unity_root_path())
    ET.SubElement(ros2_for_unity_version, "date").text = get_commit_date(get_ros2_for_unity_root_path())

    ros2_cs = ET.Element("ros2cs")
    ET.SubElement(ros2_cs, "ros2").text = get_ros2_version()
    ros2_cs_version = ET.SubElement(ros2_cs, "version")
    ET.SubElement(ros2_cs_version, "sha").text = get_git_commit(get_ros2cs_path())
    ET.SubElement(ros2_cs_version, "desc").text = get_git_description(get_ros2cs_path())
    ET.SubElement(ros2_cs_version, "date").text = get_commit_date(get_ros2cs_path())
    ET.SubElement(ros2_cs, "standalone").text = str(int(args.standalone))

    metadata_rf2u_file = get_ros2_for_unity_path().joinpath("metadata_ros2_for_unity.xml")
    write_metadata_xml(ros2_for_unity, metadata_rf2u_file)

    metadata_r2cs_file = get_ros2_for_unity_path().joinpath("metadata_ros2cs.xml")
    write_metadata_xml(ros2_cs, metadata_r2cs_file)

def write_metadata_xml(root: ET.Element, destination: pathlib.Path) -> None:
    # ET.indent requires Python 3.9+; ROS 2 Jazzy's supported Python satisfies this.
    ET.indent(root, space="   ")
    tree = ET.ElementTree(root)
    tree.write(destination, encoding="utf-8", xml_declaration=True)

if __name__ == "__main__":
    main()
