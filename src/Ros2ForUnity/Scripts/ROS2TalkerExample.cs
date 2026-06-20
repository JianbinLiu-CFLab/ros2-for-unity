// Copyright 2019-2021 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Reuses a StringBuilder and message wrapper to avoid per-frame allocations.
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

using UnityEngine;
using System.Text;

namespace ROS2
{

/// <summary>
/// Publishes <c>std_msgs/msg/String</c> messages on <c>chatter</c> every Unity frame.
/// Use <c>ros2 topic echo /chatter</c> to observe messages such as "Unity ROS2 sending: hello 1".
/// </summary>
public class ROS2TalkerExample : MonoBehaviour
{
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private IPublisher<std_msgs.msg.String> chatter_pub;
    private std_msgs.msg.String msg;
    private readonly StringBuilder msgBuilder = new StringBuilder();
    private int i;

    void Start()
    {
        // Locate the ROS2UnityComponent that owns the shared ROS 2 context for this GameObject.
        ros2Unity = GetComponent<ROS2UnityComponent>();
        if (ros2Unity == null)
        {
            Debug.LogError("ROS2TalkerExample requires ROS2UnityComponent on the same GameObject.");
        }
    }

    void Update()
    {
        if (ros2Unity == null)
        {
            return;
        }

        if (ros2Unity.Ok())
        {
            if (ros2Node == null)
            {
                ros2Node = ros2Unity.CreateNode("ROS2UnityTalkerNode");
            }
            if (chatter_pub == null)
            {
                chatter_pub = ros2Node.CreatePublisher<std_msgs.msg.String>("chatter");
            }
            if (msg == null)
            {
                msg = new std_msgs.msg.String();
            }
            if (chatter_pub == null)
            {
                return;
            }

            i++;
            // Example-only hot path: reuse the message wrapper to avoid per-frame native allocations.
            msgBuilder.Clear();
            msgBuilder.Append("Unity ROS2 sending: hello ");
            msgBuilder.Append(i);
            msg.Data = msgBuilder.ToString();
            chatter_pub.Publish(msg);
        }
    }

    void OnDestroy()
    {
        if (ros2Unity != null && ros2Node != null)
        {
            // RemoveNode disposes publishers/subscriptions owned by the node.
            ros2Unity.RemoveNode(ros2Node);
        }
        chatter_pub = null;
        ros2Node = null;
        msg = null;
    }
}

}  // namespace ROS2
