// Copyright 2019-2022 Robotec.ai.
// Modifications Copyright (c) 2026 Jianbin Liu.
//
// Fork modifications:
// - Added reference-counted ROS2ForUnity lifetime sharing.
// - Added executor-thread snapshotting so node/executable mutations are not held during callbacks.
// - Added deterministic Dispose() shutdown and bounded executor thread join.
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
using System;
using System.Collections.Generic;
using System.Threading;
using ROS2;

namespace ROS2
{

    /// <summary>
    /// The principal class for handling ros2 nodes and executables.
    /// Use this to create ros2 node, check ros2 status.
    /// Spins and executes actions (e. g. clock, sensor publish triggers) in a dedicated thread.
    /// Multiple core instances are expected to work because the underlying ROS2 layer reference-counts init/shutdown.
    /// </summary>
    public class ROS2UnityCore : IDisposable
    {
        private const int SpinIntervalMilliseconds = 2;
        private const double SpinTimeoutSeconds = 0.0001; // 100 us; keeps spin non-blocking relative to the 2 ms tick interval.
        private static readonly TimeSpan ExecutorJoinTimeout = TimeSpan.FromSeconds(2); // Allow up to 2 s for Tick() to observe quitting and exit.

        private ROS2ForUnity ros2forUnity;
        private List<ROS2Node> nodes;
        private List<INode> ros2csNodes; // For performance in spinning
        private List<Action> executableActions;
        private HashSet<Action> executableActionSet;
        private readonly List<Action> actionsSnapshot = new List<Action>();
        private readonly List<INode> nodesSnapshot = new List<INode>();
        // Snapshot versions let Tick() reuse arrays unless node/executable collections changed.
        private int collectionVersion = 0;
        private int snapshotVersion = -1;
        // volatile: Tick() reads this lock-free in its loop condition after StopExecutor() sets it.
        private volatile bool quitting = false;
        private bool disposed = false;
        private Thread executorThread;
        private readonly object mutex = new object();

        /// <summary>
        /// Returns whether this core has a live ROS2ForUnity context and has not been disposed.
        /// </summary>
        public bool Ok()
        {
            lock (mutex)
            {
                return (!disposed && nodes != null && ros2forUnity.Ok());
            }
        }

        /// <summary>
        /// Initializes ROS2ForUnity state and starts the background executor thread immediately.
        /// </summary>
        public ROS2UnityCore()
        {
            Thread threadToStart = null;
            lock (mutex)
            {
                ros2forUnity = new ROS2ForUnity();
                nodes = new List<ROS2Node>();
                ros2csNodes = new List<INode>();
                executableActions = new List<Action>();
                executableActionSet = new HashSet<Action>();

                executorThread = new Thread(() => Tick());
                // Background thread: does not prevent process exit if Dispose() is missed during shutdown.
                executorThread.IsBackground = true;
                threadToStart = executorThread;
            }
            threadToStart.Start();
        }

        /// <summary>
        /// Creates a uniquely named ROS 2 node managed by this core.
        /// </summary>
        public ROS2Node CreateNode(string name)
        {
            lock (mutex)
            {
                ThrowIfDisposed();
                foreach (ROS2Node n in nodes)
                {  // Assumed to be a rare operation on rather small (<1k) list
                    if (n.name == name)
                    {
                        throw new InvalidOperationException("Cannot create node " + name + ". A node with this name already exists!");
                    }
                }
                ROS2Node node = new ROS2Node(name);
                nodes.Add(node);
                ros2csNodes.Add(node.node);
                collectionVersion++;
                return node;
            }
        }

        /// <summary>
        /// Removes and disposes a node previously created by this core.
        /// </summary>
        public void RemoveNode(ROS2Node node)
        {
            RemoveNode(node, true);
        }

        /// <summary>
        /// Removes a node from this core without disposing it.
        /// </summary>
        public void DetachNode(ROS2Node node)
        {
            RemoveNode(node, false);
        }

        /// <summary>
        /// Removes a node and optionally disposes it.
        /// </summary>
        public void RemoveNode(ROS2Node node, bool dispose)
        {
            if (node == null)
            {
                return;
            }

            bool removed = false;
            lock (mutex)
            {
                if (nodes != null)
                {
                    removed = nodes.Remove(node);
                    bool removedRos2csNode = ros2csNodes.Remove(node.node);
                    if (removed || removedRos2csNode)
                    {
                        collectionVersion++;
                    }
                }
            }

            if (dispose && removed)
            {
                node.Dispose();
            }
        }

        /// <summary>
        /// Works as a simple executor registration analogue. These functions will be called with each Tick()
        /// Actions need to take care of correct call resolution by checking in their body (TODO)
        /// Make sure actions are lightweight (TODO - separate out threads for spinning and executables?)
        /// </summary>
        public void RegisterExecutable(Action executable)
        {
            lock (mutex)
            {
                ThrowIfDisposed();
                if (executableActionSet.Add(executable))
                {
                    executableActions.Add(executable);
                    collectionVersion++;
                }
            }
        }

        /// <summary>
        /// Removes an executable action from the background tick loop.
        /// </summary>
        public void UnregisterExecutable(Action executable)
        {
            lock (mutex)
            {
                if (executableActions != null)
                {
                    if (executableActionSet.Remove(executable))
                    {
                        executableActions.Remove(executable);
                        collectionVersion++;
                    }
                }
            }
        }

        /// <summary>
        /// "Executor" thread will tick all clocks and spin the node
        /// </summary>
        private void Tick()
        {
            while (!quitting)
            {
                bool hasSnapshot = false;

                lock (mutex)
                {
                    if (!quitting && !disposed && ros2forUnity != null && nodes != null && ros2forUnity.Ok())
                    {
                        if (snapshotVersion != collectionVersion)
                        {
                            actionsSnapshot.Clear();
                            actionsSnapshot.AddRange(executableActions);
                            nodesSnapshot.Clear();
                            nodesSnapshot.AddRange(ros2csNodes);
                            snapshotVersion = collectionVersion;
                        }
                        hasSnapshot = true;
                    }
                }

                if (hasSnapshot)
                {
                    foreach (Action action in actionsSnapshot)
                    {
                        try
                        {
                            action();
                        }
                        catch (Exception e)
                        {
                            Debug.LogException(e);
                        }
                    }

                    if (nodesSnapshot.Count > 0)
                    {
                        try
                        {
                            Ros2cs.SpinOnce(nodesSnapshot, SpinTimeoutSeconds);
                        }
                        catch (Exception e)
                        {
                            if (!quitting)
                            {
                                Debug.LogException(e);
                            }
                        }
                    }
                }
                Thread.Sleep(SpinIntervalMilliseconds);
            }
        }

        /// <summary>
        /// Compatibility alias for older callers; new code should call Dispose().
        /// </summary>
        public void DestroyNow()
        {
            Dispose();
        }

        /// <summary>
        /// Stops the executor, disposes nodes, and releases the shared ROS2ForUnity context.
        /// </summary>
        public void Dispose()
        {
            lock (mutex)
            {
                if (disposed)
                {
                    return;
                }

                // Mark disposal as started before joining/disposing to make concurrent Dispose calls idempotent.
                disposed = true;
            }

            StopExecutor();
            DisposeNodes();

            ROS2ForUnity instance = null;
            lock (mutex)
            {
                instance = ros2forUnity;
                ros2forUnity = null;
                executableActions = null;
                executableActionSet = null;
                nodes = null;
                ros2csNodes = null;
                actionsSnapshot.Clear();
                nodesSnapshot.Clear();
            }

            if (instance != null)
            {
                instance.DestroyROS2ForUnity();
            }
        }

        private void StopExecutor()
        {
            Thread threadToJoin = null;
            lock (mutex)
            {
                quitting = true;
                threadToJoin = executorThread;
            }

            if (threadToJoin != null && threadToJoin != Thread.CurrentThread)
            {
                if (!threadToJoin.Join(ExecutorJoinTimeout))
                {
                    Debug.LogWarning("ROS2UnityCore executor thread did not stop within 2 seconds");
                }
            }

            lock (mutex)
            {
                executorThread = null;
            }
        }

        private void DisposeNodes()
        {
            List<ROS2Node> nodesToDispose = null;
            lock (mutex)
            {
                if (nodes != null)
                {
                    nodesToDispose = new List<ROS2Node>(nodes);
                    nodes.Clear();
                    ros2csNodes.Clear();
                    collectionVersion++;
                }
            }

            if (nodesToDispose == null)
            {
                return;
            }

            foreach (ROS2Node node in nodesToDispose)
            {
                try
                {
                    node.Dispose();
                }
                catch (Exception e)
                {
                    Debug.LogException(e);
                }
            }
        }

        private void ThrowIfDisposed()
        {
            if (disposed)
            {
                throw new ObjectDisposedException(nameof(ROS2UnityCore));
            }
        }
    }

}  // namespace ROS2
