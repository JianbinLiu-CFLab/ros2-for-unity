// Copyright 2019-2021 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Validates that ROS2UnityComponent is present before creating the service node.
// - Keeps the example inside the ROS2 namespace for consistency with other examples.
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

using System.Collections;
using System.Collections.Generic;
using UnityEngine;

using addTwoIntsReq = example_interfaces.srv.AddTwoInts_Request;
using addTwoIntsResp = example_interfaces.srv.AddTwoInts_Response;

namespace ROS2
{

/// <summary>
/// Hosts an <c>example_interfaces/srv/AddTwoInts</c> service named <c>add_two_ints</c>.
/// Call it with <c>ros2 service call /add_two_ints example_interfaces/srv/AddTwoInts "{a: 1, b: 2}"</c>
/// and observe the request in Unity's console.
/// </summary>
public class ROS2ServiceExample : MonoBehaviour
{
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private IService<addTwoIntsReq, addTwoIntsResp> addTwoIntsService;

    void Start()
    {
        ros2Unity = GetComponent<ROS2UnityComponent>();
        if (ros2Unity == null)
        {
            Debug.LogError("ROS2ServiceExample requires ROS2UnityComponent on the same GameObject.");
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
                ros2Node = ros2Unity.CreateNode("ROS2UnityService");
            }
            if (ros2Node != null && addTwoIntsService == null)
            {
                addTwoIntsService = ros2Node.CreateService<addTwoIntsReq, addTwoIntsResp>(
                    "add_two_ints", addTwoInts);
            }
        }
    }

    public example_interfaces.srv.AddTwoInts_Response addTwoInts( example_interfaces.srv.AddTwoInts_Request msg)
    {
        Debug.Log("Incoming Service Request A=" + msg.A + " B=" + msg.B);
        example_interfaces.srv.AddTwoInts_Response response = new example_interfaces.srv.AddTwoInts_Response();
        response.Sum = msg.A + msg.B;
        return response;
    }

    void OnDestroy()
    {
        if (ros2Unity != null && ros2Node != null)
        {
            // RemoveNode disposes services owned by the node.
            ros2Unity.RemoveNode(ros2Node);
        }
        addTwoIntsService = null;
        ros2Node = null;
    }
}

}  // namespace ROS2
