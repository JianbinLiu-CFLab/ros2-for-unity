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

using System.Collections;
using System.Collections.Generic;
using System.Threading.Tasks;
using UnityEngine;
using ROS2;

using addTwoIntsReq = example_interfaces.srv.AddTwoInts_Request;
using addTwoIntsResp = example_interfaces.srv.AddTwoInts_Response;

/// <summary>
/// An example class provided for testing of basic ROS2 client
/// </summary>
public class ROS2ClientExample : MonoBehaviour
{
    private ROS2UnityComponent ros2Unity;
    private ROS2Node ros2Node;
    private IClient<addTwoIntsReq, addTwoIntsResp> addTwoIntsClient;
    private bool isRunning = false;
    private int runningCoroutines = 0;
    private Task<addTwoIntsResp> asyncTask;

    IEnumerator periodicAsyncCall()
    {
        while (ros2Unity != null && ros2Unity.Ok())
        {
            if (addTwoIntsClient == null)
            {
                yield return new WaitForSecondsRealtime(1);
                continue;
            }

            while (ros2Unity != null && ros2Unity.Ok() && addTwoIntsClient != null && !addTwoIntsClient.IsServiceAvailable())
            {
                yield return new WaitForSecondsRealtime(1);
            }

            if (ros2Unity == null || !ros2Unity.Ok() || addTwoIntsClient == null)
            {
                yield break;
            }

            addTwoIntsReq request = new addTwoIntsReq();
            request.A = Random.Range(0, 100);
            request.B = Random.Range(0, 100);
            
            asyncTask = addTwoIntsClient.CallAsync(request);
            yield return new WaitUntil(() => asyncTask.IsCompleted || ros2Unity == null || !ros2Unity.Ok());
            if (!asyncTask.IsCompleted)
            {
                yield break;
            }
            if (asyncTask.IsFaulted)
            {
                Debug.LogException(asyncTask.Exception);
            }
            else if (!asyncTask.IsCanceled)
            {
                Debug.Log("Got async answer " + asyncTask.Result.Sum);
            }
            
            yield return new WaitForSecondsRealtime(1);
        }
    }

    void Start()
    {
        ros2Unity = GetComponent<ROS2UnityComponent>();
        if (ros2Unity == null)
        {
            Debug.LogError("ROS2ClientExample requires ROS2UnityComponent on the same GameObject.");
        }
    }

    private void EnsureClient()
    {
        if (ros2Unity == null)
        {
            return;
        }

        if (ros2Unity.Ok())
        {
            if (ros2Node == null)
            {
                ros2Node = ros2Unity.CreateNode("ROS2UnityClient");
                addTwoIntsClient = ros2Node.CreateClient<addTwoIntsReq, addTwoIntsResp>(
                    "add_two_ints");
            }
        }
    }

    void Update()
    {
        EnsureClient();
        if (addTwoIntsClient == null)
        {
            return;
        }

        if (!isRunning)
        {
            isRunning = true;

            StartCoroutine(RunTracked(periodicAsyncCall()));
        }
    }

    private IEnumerator RunTracked(IEnumerator routine)
    {
        runningCoroutines++;
        try
        {
            yield return StartCoroutine(routine);
        }
        finally
        {
            runningCoroutines--;
            if (runningCoroutines <= 0)
            {
                runningCoroutines = 0;
                isRunning = false;
            }
        }
    }
}
