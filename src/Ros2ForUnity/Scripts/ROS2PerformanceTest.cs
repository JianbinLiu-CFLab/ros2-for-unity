// Copyright 2019-2021 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
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
using System.Threading;

namespace ROS2
{

/// <summary>
/// An example class provided for performance testing of ROS2 communication
/// </summary>
public class ROS2PerformanceTest : MonoBehaviour
{
    public int messageSize = 10000;
    public int rate = 10;
    private int interval_ms = 100;
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private IPublisher<sensor_msgs.msg.PointCloud2> perf_pub;
    private sensor_msgs.msg.PointCloud2 msg;
    private bool initialized = false;
    private volatile bool quitting = false;
    private Thread publishThread;
    private readonly object msgMutex = new object();

    void Start()
    {
        ros2Unity = GetComponent<ROS2UnityComponent>();
        if (ros2Unity == null)
        {
            Debug.LogError("ROS2PerformanceTest requires ROS2UnityComponent on the same GameObject.");
            return;
        }

        NormalizeInspectorValues();
        if (Application.isPlaying)
        {
            PrepMessage();
        }
    }

    void OnValidate()
    {
        NormalizeInspectorValues();
        if (!Application.isPlaying)
        {
            return;
        }
        PrepMessage();
    }

    private void NormalizeInspectorValues()
    {
        messageSize = Mathf.Max(1, messageSize);
        rate = Mathf.Max(1, rate);
        interval_ms = Mathf.Max(1, 1000 / rate);
    }

    private void Publish()
    {
        while(!quitting)
        {
            if (ros2Unity != null && ros2Unity.Ok())
            {
                if (ros2Node == null)
                {
                    ros2Node = ros2Unity.CreateNode("ros2_unity_performance_test_node");
                    perf_pub = ros2Node.CreateSensorPublisher<sensor_msgs.msg.PointCloud2>("perf_chatter");
                }
                sensor_msgs.msg.PointCloud2 messageToPublish;
                lock (msgMutex)
                {
                    messageToPublish = msg;
                }

                if (messageToPublish == null)
                {
                    Thread.Sleep(100);
                    continue;
                }

                MessageWithHeader msgWithHeader = messageToPublish as MessageWithHeader;
                if (msgWithHeader == null)
                {
                    Debug.LogError("PointCloud2 does not implement MessageWithHeader; cannot publish stamped performance message");
                    quitting = true;
                    continue;
                }
                if (!ros2Node.TryUpdateROSTimestamp(ref msgWithHeader))
                {
                    Thread.Sleep(100);
                    continue;
                }
                perf_pub.Publish(messageToPublish);
                if (interval_ms > 0)
                {
                    Thread.Sleep(interval_ms);
                }
            }
            else
            {
                Thread.Sleep(100);
            }
        }
    }

    void FixedUpdate()
    {
        if (ros2Unity == null)
        {
            return;
        }

        if (!initialized)
        {
            publishThread = new Thread(() => Publish());
            publishThread.IsBackground = true;
            publishThread.Start();
            initialized = true;
        }
    }

    void OnDestroy()
    {
        quitting = true;
        if (publishThread != null && publishThread != Thread.CurrentThread)
        {
            if (!publishThread.Join(2000))
            {
                Debug.LogWarning("ROS2PerformanceTest publish thread did not stop within 2 seconds");
            }
            publishThread = null;
        }
        if (ros2Unity != null && ros2Node != null)
        {
            try
            {
                ros2Unity.RemoveNode(ros2Node);
            }
            catch (System.Exception e)
            {
                Debug.LogException(e);
                if (perf_pub != null)
                {
                    try
                    {
                        perf_pub.Dispose();
                    }
                    catch (System.Exception disposeException)
                    {
                        Debug.LogException(disposeException);
                    }
                }
            }
        }
        perf_pub = null;
        ros2Node = null;
        lock (msgMutex)
        {
            msg = null;
        }
    }

    private void AssignField(ref sensor_msgs.msg.PointField pf, string n, uint off, byte dt, uint count)
    {
        pf.Name = n;
        pf.Offset = off;
        pf.Datatype = dt;
        pf.Count = count;
    }

    private void PrepMessage()
    {
        NormalizeInspectorValues();
        uint count = (uint)messageSize; //point per message
        uint fieldsSize = 16;
        uint rowSize = count * fieldsSize;
        sensor_msgs.msg.PointCloud2 newMsg = new sensor_msgs.msg.PointCloud2()
        {
            Height = 1,
            Width = count,
            Is_bigendian = false,
            Is_dense = true,
            Point_step = fieldsSize,
            Row_step = rowSize,
            Data = new byte[rowSize * 1]
        };
        uint pointFieldCount = 4;
        newMsg.Fields = new sensor_msgs.msg.PointField[pointFieldCount];
        for (int i = 0; i < pointFieldCount; ++i)
        {
            newMsg.Fields[i] = new sensor_msgs.msg.PointField();
        }

        AssignField(ref newMsg.Fields[0], "x", 0, 7, 1);
        AssignField(ref newMsg.Fields[1], "y", 4, 7, 1);
        AssignField(ref newMsg.Fields[2], "z", 8, 7, 1);
        AssignField(ref newMsg.Fields[3], "intensity", 12, 7, 1);
        float[] pointsArray = new float[count * newMsg.Fields.Length];

        var floatIndex = 0;
        for (int i = 0; i < count; ++i)
        {
            float intensity = 100;
            pointsArray[floatIndex++] = 1;
            pointsArray[floatIndex++] = 2;
            pointsArray[floatIndex++] = 3;
            pointsArray[floatIndex++] = intensity;
        }
        System.Buffer.BlockCopy(pointsArray, 0, newMsg.Data, 0, newMsg.Data.Length);
        newMsg.SetHeaderFrame("pc");
        lock (msgMutex)
        {
            msg = newMsg;
        }
    }
}

}  // namespace ROS2
