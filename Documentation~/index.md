# ODin's ECS overview

This package adds Odin support to Unity's Entities package. The original Entities package is part of Unity's Data-Oriented Technology Stack (DOTS), and provides a data-oriented implementation of the Entity Component System (ECS) architecture.

## Package installation

To use this package, you must have Unity version 2022.3.0f1 and later installed.
To simplify your IDE expirience I recommend using VSCode. and getting the Unity package for Visual Studio. This will ensure open a .cs file opens VS Code
if you set it in `Preferences>External Tools`. This will automatically create a .vscode folder, with a `launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Attach to Unity",
            "type": "vstuc",
            "request": "attach",
        }
     ]
}
```
This adds debugging support for attaching to unity and breakpointing `.cs`. If you also want to debug `.odin` simply add:
```json
{
    "name": "Attach with native",
    "type": "cppvsdbg",
    "request": "attach",
    //"preLaunchTask": "Build Debug as DLL"
},
```
To as a configuration in that file, and your launch menu should now be able to debug native code, like Odin. Do note the preLaunchTask, which can be uncommented if you want to ensure that the DLL has been built before you attach! Note that it does require a `tasks.json` in the `.vscode` folder.
```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Build Debug as DLL",
            "type": "shell",
            "command": "odin build .\\Assets\\odecs\\ -out:Assets/odecs/out/odecs.dll -o:minimal -debug -build-mode:dll",
            "group": {
                "kind": "build",
                "isDefault": true
            }
        }
    ]
}
```
Adding this task also means you can do `CTRL+SHIFT+P > Tasks: Run Task > Build Debug as DLL` to build your DLL!

To install the package, open the Package Manager window (**Window &gt; Package Manager**) and perform the following options:
<!-- * [Add the package from its Git URL](xref:upm-ui-giturl) -->
