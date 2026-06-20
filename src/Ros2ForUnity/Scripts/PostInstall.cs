// Copyright 2019-2022 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Validates metadata XML before copying it into Unity Player output.
// - Copies versioned Linux native libraries that Unity's default asset pipeline skips.
// - Keeps ros2cs metadata beside platform plugin libraries after each Player build.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Xml;
using UnityEngine;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;

namespace ROS2
{

/// <summary>
/// An internal class responsible for installing ros2-for-unity metadata files 
/// </summary>
internal class PostInstall : IPostprocessBuildWithReport
{
    // 0 = default priority; this step currently has no dependency on other post-build processors.
    public int callbackOrder { get { return 0; } }

    private static void ValidateMetadataXml(string path)
    {
        try {
            var metadata = new XmlDocument { XmlResolver = null };
            metadata.Load(path);
        } catch (Exception e) {
            throw new BuildFailedException("Cannot copy ROS2 metadata after build. Invalid XML: " + path + ". " + e.Message);
        }
    }

    /// <summary>
    /// Copies ROS 2 metadata XML and versioned native libraries to the Player output.
    /// Unity's asset pipeline does not copy these runtime support files automatically.
    /// </summary>
    public void OnPostprocessBuild(BuildReport report)
    {
        var r2fuMetadataName = "metadata_ros2_for_unity.xml";
        var r2csMetadataName = "metadata_ros2cs.xml";

        // FileUtil.CopyFileOrDirectory: All file separators should be forward ones "/".
        var r2fuMeta = ROS2ForUnity.GetRos2ForUnityPath() + "/" + r2fuMetadataName; 
        var r2csMeta = ROS2ForUnity.GetPluginPath() + "/" + r2csMetadataName;
        var outputDir = Directory.GetParent(report.summary.outputPath);
        if (outputDir == null) {
            throw new InvalidOperationException(
                "Cannot copy ROS2 metadata after build. Build output has no parent directory: " +
                report.summary.outputPath);
        }
        var execFilename = Path.GetFileNameWithoutExtension(report.summary.outputPath);
        // Unity Player output layout: <ExeName>_Data/ for managed assets and <ExeName>_Data/Plugins/ for plugin libraries.
        var dataDir = outputDir + "/" + execFilename + "_Data";
        var pluginsDir = dataDir + "/Plugins";
        Directory.CreateDirectory(dataDir);
        Directory.CreateDirectory(pluginsDir);
        if (!File.Exists(r2fuMeta) || !File.Exists(r2csMeta)) {
            throw new FileNotFoundException(
                "Cannot copy ROS2 metadata after build. Missing source: " +
                (!File.Exists(r2fuMeta) ? r2fuMeta : r2csMeta));
        }
        ValidateMetadataXml(r2fuMeta);
        ValidateMetadataXml(r2csMeta);

        FileUtil.CopyFileOrDirectory(
            r2fuMeta, dataDir + "/" + r2fuMetadataName);
        if (EditorUserBuildSettings.activeBuildTarget == BuildTarget.StandaloneLinux64) {
            FileUtil.CopyFileOrDirectory(
                r2csMeta, pluginsDir + "/" + r2csMetadataName);

            // Copy versioned libraries (Unity skips them)
            Regex soWithVersionReg = new Regex(@".*\.so(\.[0-9]+)+$");
            var versionedLibs = new List<String>(Directory.GetFiles(ROS2ForUnity.GetPluginPath()))
                                    .Where(path => soWithVersionReg.IsMatch(path))
                                    .ToList();
            foreach (var libPath in versionedLibs) {
                FileUtil.CopyFileOrDirectory(
                    libPath, pluginsDir + "/" + Path.GetFileName(libPath));
            }
        } else {
            var windowsPluginsDir = pluginsDir + "/x86_64";
            Directory.CreateDirectory(windowsPluginsDir);
            FileUtil.CopyFileOrDirectory(
                r2csMeta, windowsPluginsDir + "/" + r2csMetadataName);
        }
    }

}

}
#endif
