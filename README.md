
Ros2 For Unity
===============

> [!NOTE]  
> This project is officially supported for [AWSIM](https://github.com/tier4/AWSIM) users of Autoware. However, the Robotec team is unable to provide support and maintain the project for the general
> community. If you are looking for an alternative to Unity3D, [Open 3D Engine (O3DE)](https://o3de.org/) is a great, open-source and free simulation engine with excellent [ROS 2 integration](https://development--o3deorg.netlify.app/docs/user-guide/interactivity/), which Robotec is actively supporting and developing. 

ROS2 For Unity is a high-performance communication solution to connect Unity3D and ROS2 ecosystem in a ROS2 "native" way. Communication is not bridged as in several other solutions, but instead it uses ROS2 middleware stack (rcl layer and below), which means you can have ROS2 nodes in your simulation.
Advantages of this module include:
- High performance - higher throughput and considerably lower latencies comparing to bridging solutions.
- Your simulation entities are real ROS2 nodes / publishers / subscribers. They will behave correctly with e.g. command line tools such as `ros2 topic`. They will respect QoS settings and can use ROS2 native time.
- The module supplies abstractions and tools to use in your Unity project, including transformations, sensor interface, a clock, spinning loop wrapped in a MonoBehavior, handling initialization and shutdown.
- Supports all standard ROS2 messages.
- Custom messages are generated automatically with build, using standard ROS2 way. It is straightforward to generate and use them without having to define `.cs` equivalents by hand.
- The module is wrapped as a Unity asset.

## Maintained integration line

For the JianbinLiu-CFLab fork, `main` is the maintained integration line.

This fork consumes the maintained ros2cs fork through `ros2cs.repos`:

```text
https://github.com/JianbinLiu-CFLab/ros2cs.git
version: main
```

The upstream RobotecAI repositories remain the original source and licensing history, but they are not the active integration target for this Jazzy/R2FU maintenance line. Upstream changes should be reviewed and cherry-picked deliberately.

## Current verification status

Current local maintenance evidence is centered on Windows 10 LTSC + ROS 2 Jazzy.

Verified on the current maintenance line:

- Build GREEN: Windows-native Jazzy standalone asset build through `build.ps1`, using the canonical `ros2cs` workspace and documented short-path Windows layout.
- Latest source release: [`v0.3.0-jazzy-win64-preview.1`](https://github.com/JianbinLiu-CFLab/ros2-for-unity/releases/tag/v0.3.0-jazzy-win64-preview.1).
- Latest packaged Windows artifact: still [`v0.2.0-jazzy-win64-preview.1`](https://github.com/JianbinLiu-CFLab/ros2-for-unity/releases/tag/v0.2.0-jazzy-win64-preview.1) until the standalone zip is regenerated from the `v0.3.0` source line.
- Current `v0.2.0` artifact: `Ros2ForUnity_jazzy_standalone_windows_x86_64.zip` with SHA256 `497a245edbaff247f4c428d4f131a8c1d93c5be2fc6d763cb1e4624586c67e82`.
- Managed/native regression signal: `ros2cs_tests` reports 77 NUnit tests passed, 0 failed, 0 skipped.

Not yet claimed:

- Unity Load GREEN for the next `v0.3.0` artifact: the prior Unity Load route is known, but the refreshed runtime artifact should be regenerated, re-imported, and rechecked before upgrading the claim.
- Runtime Smoke GREEN: runtime pub/sub, service/client, graph discovery, sensor scene behavior, and repeated Play/Stop still need dedicated Unity-side validation on the refreshed artifact.
- Product GREEN: Player export, release signing, deterministic artifact packaging, and broader scenario validation are still later gates.

Test coverage note: current R2FU validation intentionally uses `ros2cs_tests` as the managed/native binding regression signal. Full upstream ROS interface package test sweeps are not claimed here.

Core `ros2cs` assemblies and generated message assemblies stay on `netstandard2.0`; `ros2cs` tests and examples use modern .NET where applicable. R2FU Unity scripts remain Unity/C# runtime scripts and are validated through Unity-side stages.

## Platforms

Maintained/validated OS status:
- Windows 10 LTSC + ROS 2 Jazzy: current active maintenance target.
- Windows 11 + ROS 2 Jazzy: expected to work through the same Windows toolchain, but should be verified separately before release claims.
- Ubuntu 20.04/22.04/24.04: legacy instructions are retained, but this Jazzy maintenance line has not recently revalidated Ubuntu.


ROS 2 distribution status:
- Jazzy: current active maintenance target.
- Humble: expected compatibility target, not the current evidence baseline.
- Foxy/Galactic/Rolling: historical or experimental; do not treat as validated for this fork without a fresh build/test record.

Supported Unity3d:
- 2020+
- 6000+

Older versions of Unity3d may work, but the editor executable most probably won't be detected properly by deployment script. This would require user confirmation for using unsupported version.

This asset can be prepared in two flavours:

- standalone mode, where no ROS2 installation is required on target machine, e.g., your Unity3D simulation server. All required dependencies are installed and can be used e.g. as a complete set of Unity3D plugins.
- overlay mode, where the ROS2 installation is required on target machine. Only asset libraries and generated messages are installed therefore ROS2 instance must be sourced.

## Releases

RobotecAI pre-built [releases](https://github.com/RobotecAI/ros2-for-unity/releases) remain useful historical artifacts for their original supported ROS 2 and Unity versions.

For this fork's Jazzy Windows maintenance line, use the JianbinLiu-CFLab releases:

- latest source release: [`v0.3.0-jazzy-win64-preview.1`](https://github.com/JianbinLiu-CFLab/ros2-for-unity/releases/tag/v0.3.0-jazzy-win64-preview.1)
- latest packaged Windows artifact: [`v0.2.0-jazzy-win64-preview.1`](https://github.com/JianbinLiu-CFLab/ros2-for-unity/releases/tag/v0.2.0-jazzy-win64-preview.1)
- previous: [`v0.1.0-jazzy-win64-preview.1`](https://github.com/JianbinLiu-CFLab/ros2-for-unity/releases/tag/v0.1.0-jazzy-win64-preview.1)

## Building

> **Note:** The project will pull `ros2cs` into the workspace, which also functions independently as it is a more general project aimed at any `C# / .Net` environment.
It has its own README and scripting, but for building the Unity Asset, please use instructions and scripting in this document instead, unless you also wish to run tests or examples for `ros2cs`.

Please see OS-specific instructions:
- [Instructions for Ubuntu](README-UBUNTU.md)
- [Instructions for Windows](README-WINDOWS.md)

## Custom messages

Custom messages can be included in the build by either:
* listing them in `ros2_for_unity_custom_messages.repos` file, or
* manually inserting them in `src/ros2cs` directory. If the folder doesn't exist, you must pull repositories first (see building steps for each OS).

## Installation

1. Perform building steps described in the OS-specific readme or download pre-built Unity package. Do not source `ros2-for-unity` nor `ros2cs` project into ROS2 workspace.
1. Open or create Unity project.
1. Import asset into project:
    1. copy `install/asset/Ros2ForUnity` into your project `Assets` folder, or
    1. if you have deployed an `.unitypackage` - import it in Unity Editor by selecting `Import Package` -> `Custom Package`

## Usage

**Prerequisites**

* If your build was prepared with `--standalone` flag then you are fine, and all you have to do is run the editor

otherwise

* source ROS2 which matches the `Ros2ForUnity` version, then run the editor from within the very same terminal/console.

**Initializing Ros2ForUnity**

1. Initialize `Ros2ForUnity` by creating a "hook" object which will be your wrapper around ROS2. You have two options:
    1. `ROS2UnityComponent` based on `MonoBehaviour` which must be attached to a `GameObject` somewhere in the scene, then:
        ```c#
        using ROS2;
        ...
        // Example method of getting component, if ROS2UnityComponent lives in different GameObject, just use different get component methods.
        ROS2UnityComponent ros2Unity = GetComponent<ROS2UnityComponent>();
        ```
    1. or `ROS2UnityCore` which is a standard class that can be created anywhere
        ```c#
        using ROS2;
        ...
        ROS2UnityCore ros2Unity = new ROS2UnityCore();
        ```
1. Create a node. You must first check if `Ros2ForUnity` is initialized correctly:
    ```c#
    private ROS2Node ros2Node;
    ...
    if (ros2Unity.Ok()) {
        ros2Node = ros2Unity.CreateNode("ROS2UnityListenerNode");
    }
    ```

**Publishing messages:**

1. Create publisher
    ```c#
    private IPublisher<std_msgs.msg.String> chatter_pub;
    ...
    if (ros2Unity.Ok()){
        chatter_pub = ros2Node.CreatePublisher<std_msgs.msg.String>("chatter"); 
    }
    ```
1. Send messages
    ```c#
    std_msgs.msg.String msg = new std_msgs.msg.String();
    msg.Data = "Hello Ros2ForUnity!";
    chatter_pub.Publish(msg);
    ```

**Subscribing to a topic**

1. Create subscriber:
    ```c#
    private ISubscription<std_msgs.msg.String> chatter_sub;
    ...
    if (ros2Unity.Ok()) {
        chatter_sub = ros2Node.CreateSubscription<std_msgs.msg.String>(
            "chatter", msg => Debug.Log("Unity listener heard: [" + msg.Data + "]"));
    }
    ```

**Creating a service**

1. Create service body:
    ```c#
    public example_interfaces.srv.AddTwoInts_Response addTwoInts( example_interfaces.srv.AddTwoInts_Request msg)
    {
        example_interfaces.srv.AddTwoInts_Response response = new example_interfaces.srv.AddTwoInts_Response();
        response.Sum = msg.A + msg.B;
        return response;
    }
    ```

1. Create a service with a service name and callback:
    ```c#
    IService<example_interfaces.srv.AddTwoInts_Request, example_interfaces.srv.AddTwoInts_Response> service = 
        ros2Node.CreateService<example_interfaces.srv.AddTwoInts_Request, example_interfaces.srv.AddTwoInts_Response>(
            "add_two_ints", addTwoInts);
    ```

**Calling a service**

1. Create a client:
    ```c#
    private IClient<example_interfaces.srv.AddTwoInts_Request, example_interfaces.srv.AddTwoInts_Response> addTwoIntsClient;
    ...
    addTwoIntsClient = ros2Node.CreateClient<example_interfaces.srv.AddTwoInts_Request, example_interfaces.srv.AddTwoInts_Response>(
        "add_two_ints");
    ```

1. Create a request and call a service:
    ```c#
    example_interfaces.srv.AddTwoInts_Request request = new example_interfaces.srv.AddTwoInts_Request();
    request.A = 1;
    request.B = 2;
    var response = addTwoIntsClient.Call(request);
    ```

1. You can also make an async call:
    ```c#
    Task<example_interfaces.srv.AddTwoInts_Response> asyncTask = addTwoIntsClient.CallAsync(request);
    yield return new WaitUntil(() => asyncTask.IsCompleted);
    if (asyncTask.IsFaulted) {
        Debug.LogException(asyncTask.Exception);
    } else if (!asyncTask.IsCanceled) {
        Debug.Log("Got answer " + asyncTask.Result.Sum);
    }
    ```
### Examples

1. Create a top-level object containing `ROS2UnityComponent.cs`. This is the central `Monobehavior` for `Ros2ForUnity` that manages all the nodes. Refer to class documentation for details.
    > **Note:** Each example script looks for `ROS2UnityComponent` in its own game object. However, this is not a requirement, just example implementation.

**Topics**
1. Add `ROS2TalkerExample.cs` script to the very same game object.
1. Add `ROS2ListenerExample.cs` script to the very same game object.

Once you start the project in Unity, you should be able to see two nodes talking with each other in  Unity Editor's console or use `ros2 node list` and `ros2 topic echo /chatter` to verify ros2 communication.

**Services**
1. Add `ROS2ServiceExample.cs` script to the very same game object.
1. Add `ROS2ClientExample.cs` script to the very same game object.

Once you start the project in Unity, you should be able to see client node calling an example service.

## Acknowledgements 

Open-source release of ROS2 For Unity was made possible through cooperation with [TIER IV](https://tier4.jp). Thanks to encouragement, support and requirements driven by TIER IV the project was significantly improved in terms of portability, stability, core structure and user-friendliness.
