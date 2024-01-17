package unity_interface_bridge

import "core:runtime"
import "core:strings"
import "core:mem"


ENABLE_UNITY_COLLECTIONS_CHECKS :: #config(ENABLE_UNITY_COLLECTIONS_CHECKS, true)
UNITY_DOTS_DEBUG :: #config(UNITY_DOTS_DEBUG, false)

odecs_context: runtime.Context

// IUnityInterfaces
IUnityInterfaces :: struct
{
    GetInterface: proc "std" (guid: UnityInterfaceGUID) -> ^IUnityInterface,   
    RegisterInterface: proc "std" (guid: UnityInterfaceGUID, ptr: ^IUnityInterface),
    GetInterfaceSplit: proc "std" (guidHigh: u64, guidLow: u64) -> ^IUnityInterface,
    RegisterInterfaceSplit: proc "std" (guidHigh: u64, guidLow:u64, ptr: ^IUnityInterface),
}
IUnityInterface :: struct {}
UnityInterfaceGUID :: struct
{
    m_GUIDHigh, m_GUIDLow: u64
}

// IUnityLog
IUnityLog_GUID :: UnityInterfaceGUID {0x9E7507fA5B444D5D, 0x92FB979515EA83FC};
IUnityLog :: struct
{
    Log: proc "std" (type: UnityLogType, message, fileName: cstring, fileLine: i32),
};
UnityLogType :: enum
{
    Error = 0,
    Warning = 2,
    Log = 3,
    Exception = 4,
}

// IUnityMemoryManager
IUnityMemoryManager_GUID :: UnityInterfaceGUID {0xBAF9E57C61A811EC, 0xC5A7CC7861A811EC}
IUnityMemoryManager :: struct
{
    CreateAllocator : proc "std" (areaName: cstring, objectName: cstring) -> ^UnityAllocator,
    DestroyAllocator: proc "std" (allocator: ^UnityAllocator),
    
    Allocate   : proc "std" (allocator: ^UnityAllocator, size, align: u32, file: cstring, line: i32) -> rawptr,
    Deallocate : proc "std" (allocator: ^UnityAllocator, ptr: rawptr, file: cstring, line: i32),
    Reallocate : proc "std" (allocator: ^UnityAllocator, ptr: rawptr, size, align: u32, file: cstring, line: i32) -> rawptr,
};
UnityAllocator :: struct {}

unityLogPtr: ^IUnityLog
unityMemPtr: ^IUnityMemoryManager
unity_allocator: ^UnityAllocator

@export 
UnityPluginLoad :: proc "std" (unityInterfacesPtr: ^IUnityInterfaces)
{
    //Get the unity log pointer once the Unity plugin gets loaded
    unityLogPtr = (^IUnityLog)(unityInterfacesPtr.GetInterface(IUnityLog_GUID))
    unityMemPtr = (^IUnityMemoryManager)(unityInterfacesPtr.GetInterface(IUnityMemoryManager_GUID))
    unity_allocator = unityMemPtr.CreateAllocator("Odin Memory", "Main Context")

    odecs_context = runtime.default_context()

    // Create working allocator from Unity Allocator
    // odecs_context.allocator = {
    //     procedure = proc(allocator_data: rawptr, mode: runtime.Allocator_Mode,
    //         size, alignment: int,
    //         old_memory: rawptr, old_size: int,
    //         location: = #caller_location) -> ([]byte, runtime.Allocator_Error) {
    //             path_name := strings.clone_to_cstring(location.file_path)
    //             defer delete(path_name)
    //             switch mode {
    //                 case .Alloc, .Alloc_Non_Zeroed:
    //                     return mem.byte_slice(unityMemPtr.Allocate(unity_allocator, u32(size), u32(alignment), path_name, location.line), size), .None

    //                 case .Free:
    //                     unityMemPtr.Deallocate(unity_allocator, old_memory, path_name, location.line)

    //                 case .Free_All:
    //                     return nil, .Mode_Not_Implemented

    //                 case .Resize:
    //                     if old_memory == nil {
    //                         return mem.byte_slice(unityMemPtr.Allocate(unity_allocator, u32(size), u32(alignment), path_name, location.line), size), .None
    //                     }
    //                     return mem.byte_slice(unityMemPtr.Reallocate(unity_allocator, old_memory, u32(size), u32(alignment), path_name, location.line), size), .None

    //                 case .Query_Features:
    //                     set := (^mem.Allocator_Mode_Set)(old_memory)
    //                     if set != nil {
    //                         set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Query_Features}
    //                     }
    //                     return nil, nil

    //                 case .Query_Info:
    //                     return nil, .Mode_Not_Implemented
    //             }
                
    //             return nil, nil
    //         }
    //     }

    // Create working logger from Unity Logger
    odecs_context.logger = {
        options = {.Short_File_Path, .Line},
        procedure = proc(data: rawptr, level: runtime.Logger_Level, text_raw: string, options: runtime.Logger_Options, location := #caller_location) {
            logType: UnityLogType
            switch level {
                case .Debug, .Info:
                    logType = .Log
                case .Warning:
                    logType = .Warning
                case .Error:
                    logType = .Error
                case .Fatal:
                    logType = .Exception
            }
            text := strings.clone_to_cstring(text_raw)
            path_name := strings.clone_to_cstring(location.file_path)
            unityLogPtr.Log(logType, text, path_name, location.line)
            delete(text)
            delete(path_name)
        },
    }
}

@export 
UnityPluginUnload :: proc "std" () {
    unityMemPtr.DestroyAllocator(unity_allocator)
    unity_allocator = nil
    unityLogPtr = nil
    unityMemPtr = nil
}

@export
GetDefaultOdecsContext :: proc "c" () -> ^runtime.Context {
    return &odecs_context
}