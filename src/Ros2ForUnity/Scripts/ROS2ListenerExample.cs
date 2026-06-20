// Copyright 2019-2021 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Validates that ROS2UnityComponent is present before creating the node.
// - Removes the example node on destruction so copied examples show explicit cleanup.
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

using System;
using UnityEngine;

namespace ROS2
{

/// <summary>
/// Subscribes to <c>std_msgs/msg/String</c> messages on <c>chatter</c>.
/// Use it with <see cref="ROS2TalkerExample"/> or <c>ros2 topic pub</c>; received data is printed with <c>Debug.Log</c>.
/// </summary>
public class ROS2ListenerExample : MonoBehaviour
{
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private ISubscription<std_msgs.msg.String> chatter_sub;

    void Start()
    {
        ros2Unity = GetComponent<ROS2UnityComponent>();
        if (ros2Unity == null)
        {
            Debug.LogError("ROS2ListenerExample requires ROS2UnityComponent on the same GameObject.");
        }
    }

    void Update()
    {
        if (ros2Unity == null)
        {
            return;
        }

        if (ros2Node == null && ros2Unity.Ok())
        {
            ros2Node = ros2Unity.CreateNode("ROS2UnityListenerNode");
        }
        if (ros2Node != null && chatter_sub == null && ros2Unity.Ok())
        {
            chatter_sub = ros2Node.CreateSubscription<std_msgs.msg.String>(
              "chatter", msg => Debug.Log("Unity listener heard: [" + msg.Data + "]"));
        }
    }

    void OnDestroy()
    {
        if (ros2Unity != null && ros2Node != null)
        {
            // RemoveNode disposes publishers/subscriptions owned by the node.
            ros2Unity.RemoveNode(ros2Node);
        }
        chatter_sub = null;
        ros2Node = null;
    }
}

}  // namespace ROS2
