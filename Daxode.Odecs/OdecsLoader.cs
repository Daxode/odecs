using System;
using System.IO;
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Entities;
using MonoPInvokeCallbackAttribute = AOT.MonoPInvokeCallbackAttribute;
using UnityEditor;


// Ensure DLL is only loaded in playmode
[InitializeOnLoad]
static class odecs_initializer {
    static odecs_initializer() {
        EditorApplication.playModeStateChanged += state => {
            if (state == PlayModeStateChange.EnteredPlayMode)
                odecs_calls.load_calls();
            if (state == PlayModeStateChange.ExitingPlayMode)
                odecs_calls.unload_calls();
        };
    }
}

[BurstCompile]
unsafe static class odecs_calls {

    // C# -> Odin
    struct UnmanagedData {
        IntPtr loaded_lib;
        public void load_calls() {
            if (loaded_lib==IntPtr.Zero)
                loaded_lib = win32.LoadLibrary(Path.GetFullPath("Packages/odecs/Daxode.Odecs/out/odecs.dll")); // TODO: this won't work for builds and Unity Package Manager location
            init = win32.GetProcAddress(loaded_lib, "init");
            Rotate =  win32.GetProcAddress(loaded_lib, "Rotate");
        }

        public void unload_calls() {
            if (loaded_lib != IntPtr.Zero)
                win32.FreeLibrary(loaded_lib);
            loaded_lib = IntPtr.Zero;
        }

        public IntPtr init;
        public IntPtr Rotate;
        public FunctionsToCallFromOdin functionsToCallFromOdin;

        public bool IsLoaded => loaded_lib != IntPtr.Zero;
    }

    public static delegate* unmanaged[Cdecl]<ref SystemState, ref EntityQuery, void*, void*, void> Rotate 
        => (delegate* unmanaged[Cdecl]<ref SystemState, ref EntityQuery, void*, void*, void>) data.Data.Rotate;

    public static bool IsAvailable => data.Data.IsLoaded;

    public static void load_calls() 
    {
        data.Data.load_calls();
        init_odecs();
    }
    [BurstCompile]
    static void init_odecs(){
        data.Data.functionsToCallFromOdin.Init();
        var init = (delegate* unmanaged[Cdecl]<ref FunctionsToCallFromOdin, void>) data.Data.init;
        init(ref data.Data.functionsToCallFromOdin);
    }
    public static void unload_calls() => data.Data.unload_calls();

    struct SpecialKey {}
    static readonly SharedStatic<UnmanagedData> data = SharedStatic<UnmanagedData>.GetOrCreate<SpecialKey>();

    // Odin -> C#
    [BurstCompile]
    struct FunctionsToCallFromOdin {
        IntPtr odecsContext;
        IntPtr entityQueryToArchetypeChunkArray;
        IntPtr getASHForComponent;
        public void Init() {
            odecsContext = Daxode.UnityInterfaceBridge.OdecsUnityBridge.GetDefaultOdecsContext();
            entityQueryToArchetypeChunkArray = BurstCompiler.CompileFunctionPointer<ToArchetypeChunkArrayFunc>(ToArchetypeChunkArray).Value;
            getASHForComponent = BurstCompiler.CompileFunctionPointer<GetASHForComponentFunc>(GetASHForComponent).Value;
        }

        // EntityQueryImpl.ToArchetypeChunkArray
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        unsafe delegate void ToArchetypeChunkArrayFunc(EntityQueryImpl* queryImpl, AllocatorManager.AllocatorHandle* allocator, NativeArray<ArchetypeChunk>* array);
        [BurstCompile]
        [MonoPInvokeCallback(typeof(ToArchetypeChunkArrayFunc))]
        static void ToArchetypeChunkArray(EntityQueryImpl* queryImpl, AllocatorManager.AllocatorHandle* allocator, NativeArray<ArchetypeChunk>* array) => *array = queryImpl->ToArchetypeChunkArray(*allocator);

        // state.m_DependencyManager->Safety.GetSafetyHandleForComponentTypeHandle
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        unsafe delegate void GetASHForComponentFunc(SystemState* state, TypeIndex* typeIndex, byte isReadOnly, AtomicSafetyHandle* ash);
        [BurstCompile]
        [MonoPInvokeCallback(typeof(GetASHForComponentFunc))]
        static void GetASHForComponent(SystemState* state, TypeIndex* typeIndex, byte isReadOnly, AtomicSafetyHandle* ash) => *ash = state->m_DependencyManager->Safety.GetSafetyHandleForComponentTypeHandle(*typeIndex, isReadOnly>0);
    }
}


// Kernel loading functions
static class win32 {
    [DllImport("kernel32")]
    public static extern IntPtr LoadLibrary(string dllToLoad);
    
    [DllImport("kernel32")]
    public static extern IntPtr GetProcAddress(IntPtr dllPtr, string functionName);
    
    [DllImport("kernel32")]
    public static extern bool FreeLibrary(IntPtr dllPtr);
}