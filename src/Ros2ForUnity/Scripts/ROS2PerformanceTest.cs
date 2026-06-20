// Copyright 2019-2021 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Adds OnDestroy cleanup for the publish thread, publisher, and ROS2 node.
// - Adds OnValidate live reload for Inspector-driven rate/message-size changes.
// - Uses thread-safe message swapping for the PointCloud2 publish loop.
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
/// A throughput generator for ROS2 communication experiments. It does not assert
/// subscriber delivery or message integrity and should not be treated as a correctness smoke test.
/// Measure externally with <c>ros2 topic hz /perf_chatter</c> or <c>ros2 topic bw /perf_chatter</c>.
/// </summary>
public class ROS2PerformanceTest : MonoBehaviour
{
    private const int DefaultMessageSize = 10000;
    private const int DefaultRateHz = 10;
    private const int MillisecondsPerSecond = 1000;
    private const int PublishRetryDelayMs = 100; // Back-off while ROS 2 is not ready or the message is not prepared.
    private const int PublishThreadJoinTimeoutMs = 2000; // Grace period for the publish thread to exit on destroy.
    private const int PointFieldCount = 4; // x, y, z, intensity.
    private const uint PointStepBytes = 16; // 4 fields (x,y,z,intensity) * 4 bytes each.
    private const uint PointCloudHeight = 1;
    private const byte PointFieldFloat32 = 7; // sensor_msgs/PointField.FLOAT32.
    private const uint PointFieldElementCount = 1;
    private const uint XOffsetBytes = 0;
    private const uint YOffsetBytes = 4;
    private const uint ZOffsetBytes = 8;
    private const uint IntensityOffsetBytes = 12;
    private const string PerformanceFrameId = "pc";

    /// <summary>
    /// Number of points per PointCloud2 message (default 10,000).
    /// </summary>
    public int messageSize = DefaultMessageSize;

    /// <summary>
    /// Publish rate in Hz (default 10). Clamped to at least 1.
    /// </summary>
    public int rate = DefaultRateHz;

    private volatile int interval_ms = MillisecondsPerSecond / DefaultRateHz;
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private IPublisher<sensor_msgs.msg.PointCloud2> perf_pub;
    private sensor_msgs.msg.PointCloud2 msg;
    private MessageWithHeader msgWithHeader;
    private bool initialized = false;
    private volatile bool quitting = false;
    private Thread publishThread;
    private readonly object msgMutex = new object();
    private static readonly byte[] pointDataPattern = CreatePointDataPattern();

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
        if (!Application.isPlaying)
        {
            NormalizeInspectorValues();
            return;
        }
        PrepMessage();
    }

    private void NormalizeInspectorValues()
    {
        messageSize = Mathf.Max(1, messageSize);
        rate = Mathf.Max(1, rate);
        interval_ms = Mathf.Max(1, MillisecondsPerSecond / rate);
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
                MessageWithHeader headerToUpdate;
                lock (msgMutex)
                {
                    messageToPublish = msg;
                    headerToUpdate = msgWithHeader;
                }

                if (messageToPublish == null)
                {
                    Thread.Sleep(PublishRetryDelayMs);
                    continue;
                }

                if (headerToUpdate == null)
                {
                    Debug.LogError("PointCloud2 does not implement MessageWithHeader; cannot publish stamped performance message");
                    quitting = true;
                    continue;
                }
                if (!ros2Node.TryUpdateROSTimestamp(ref headerToUpdate))
                {
                    Thread.Sleep(PublishRetryDelayMs);
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
                Thread.Sleep(PublishRetryDelayMs);
            }
        }
    }

    void FixedUpdate()
    {
        // Start in FixedUpdate rather than Start so ROS2UnityComponent has had a chance to initialize its executor.
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
            if (!publishThread.Join(PublishThreadJoinTimeoutMs))
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
            msgWithHeader = null;
        }
    }

    private void AssignField(ref sensor_msgs.msg.PointField pf, string n, uint off, byte dt, uint count)
    {
        pf.Name = n;
        pf.Offset = off;
        pf.Datatype = dt;
        pf.Count = count;
    }

    private static byte[] CreatePointDataPattern()
    {
        // Arbitrary constant point data for throughput testing; values have no physical meaning.
        float[] pointValues = { 1f, 2f, 3f, 100f };
        byte[] pattern = new byte[sizeof(float) * PointFieldCount];
        System.Buffer.BlockCopy(pointValues, 0, pattern, 0, pattern.Length);
        return pattern;
    }

    private void PrepMessage()
    {
        NormalizeInspectorValues();
        uint count = (uint)messageSize; // Points per message.
        uint fieldsSize = PointStepBytes;
        uint rowSize = count * fieldsSize;
        sensor_msgs.msg.PointCloud2 newMsg = new sensor_msgs.msg.PointCloud2()
        {
            Height = PointCloudHeight,
            Width = count,
            Is_bigendian = false,
            Is_dense = true,
            Point_step = fieldsSize,
            Row_step = rowSize,
            Data = new byte[rowSize]
        };
        newMsg.Fields = new sensor_msgs.msg.PointField[PointFieldCount];
        for (int i = 0; i < PointFieldCount; ++i)
        {
            newMsg.Fields[i] = new sensor_msgs.msg.PointField();
        }

        AssignField(ref newMsg.Fields[0], "x", XOffsetBytes, PointFieldFloat32, PointFieldElementCount);
        AssignField(ref newMsg.Fields[1], "y", YOffsetBytes, PointFieldFloat32, PointFieldElementCount);
        AssignField(ref newMsg.Fields[2], "z", ZOffsetBytes, PointFieldFloat32, PointFieldElementCount);
        AssignField(ref newMsg.Fields[3], "intensity", IntensityOffsetBytes, PointFieldFloat32, PointFieldElementCount);
        for (int offset = 0; offset < newMsg.Data.Length; offset += pointDataPattern.Length)
        {
            System.Buffer.BlockCopy(pointDataPattern, 0, newMsg.Data, offset, pointDataPattern.Length);
        }
        // Frame ID used by the performance test; external smoke scripts may assert this value.
        newMsg.SetHeaderFrame(PerformanceFrameId);
        MessageWithHeader newMsgWithHeader = newMsg as MessageWithHeader;
        lock (msgMutex)
        {
            msg = newMsg;
            msgWithHeader = newMsgWithHeader;
        }
    }
}

}  // namespace ROS2
