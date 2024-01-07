using System;
using System.IO;
using System.Runtime.InteropServices;
using Unity.Burst;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Core;
using Unity.Entities;
using Unity.Mathematics;
using Unity.Transforms;
using UnityEngine;
using MonoPInvokeCallbackAttribute = AOT.MonoPInvokeCallbackAttribute;

public class SpinningAuthor : MonoBehaviour
{
    [SerializeField] float degressPerSecond;

    class Baker : Baker<SpinningAuthor> {
        public override void Bake(SpinningAuthor authoring)
        {
            var entity = GetEntity(TransformUsageFlags.Dynamic);
            AddComponent(entity, new SpinSpeed {radiansPerSecond = math.radians(authoring.degressPerSecond) });
        }
    }
}

struct SpinSpeed : IComponentData {
    public float radiansPerSecond;
}

[BurstCompile]
unsafe static class odecs_calls {
    struct UnmanagedData {
        IntPtr loaded_lib;
        public void load_calls() {
            if (loaded_lib==IntPtr.Zero)
                loaded_lib = win32.LoadLibrary(Path.GetFullPath("Packages/odecs/Daxode.Odecs/out/odecs.dll"));
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
    }

    public static void load_calls() => data.Data.load_calls();
    public static void unload_calls() => data.Data.unload_calls();

    struct SpecialKey {}
    static readonly SharedStatic<UnmanagedData> data = SharedStatic<UnmanagedData>.GetOrCreate<SpecialKey>();

    [BurstCompile]
    struct FunctionsToCallFromOdin {
        IntPtr debugLog;
        public void Init() {
            debugLog = BurstCompiler.CompileFunctionPointer<DebugLog>(Log).Value;
        }

        unsafe struct FakeUntypedUnsafeList {
    #pragma warning disable 169
            [NativeDisableUnsafePtrRestriction]
            internal void* Ptr;
            internal int m_length;
            internal int m_capacity;
            internal AllocatorManager.AllocatorHandle Allocator;
            internal int padding;
    #pragma warning restore 169
        }
        [BurstCompile]
        [MonoPInvokeCallback(typeof(DebugLog))]
        unsafe static void Log (byte* str, int length){
            var text = new FakeUntypedUnsafeList { Ptr = str, m_length = length, m_capacity = length, Allocator = default,  padding = 0};
            Debug.Log($"{new FixedString512Bytes(UnsafeUtility.As<FakeUntypedUnsafeList, UnsafeText>(ref text))}");
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        unsafe delegate void DebugLog(byte* str, int length);
    }

    static FunctionsToCallFromOdin s_functionsToCallFromOdin;
    public unsafe static void  init()
    {
        s_functionsToCallFromOdin.Init();
        var odecs_init = (delegate* unmanaged[Cdecl]<ref FunctionsToCallFromOdin, void>) data.Data.init;
        odecs_init(ref s_functionsToCallFromOdin);
    }

    public static delegate* unmanaged[Cdecl]<int, LocalTransform*, SpinSpeed*, TimeData*, void> Rotate 
            => (delegate* unmanaged[Cdecl]<int, LocalTransform*, SpinSpeed*, TimeData*, void>) data.Data.Rotate;
}

static class win32 {
    [DllImport("kernel32")]
    public static extern IntPtr LoadLibrary(string dllToLoad);
    
    [DllImport("kernel32")]
    public static extern IntPtr GetProcAddress(IntPtr dllPtr, string functionName);
    
    [DllImport("kernel32")]
    public static extern bool FreeLibrary(IntPtr dllPtr);
}

[BurstCompile]
partial struct odecs_setup_system : ISystem {
    ComponentTypeHandle<SpinSpeed> speedHandle;
    ComponentTypeHandle<LocalTransform> transformHandle;
    EntityQuery query;

    public unsafe void OnCreate(ref SystemState state){
        odecs_calls.load_calls();
        odecs_calls.init();
        speedHandle = SystemAPI.GetComponentTypeHandle<SpinSpeed>(true);
        transformHandle = SystemAPI.GetComponentTypeHandle<LocalTransform>();
        query = SystemAPI.QueryBuilder().WithAll<SpinSpeed, LocalTransform>().Build();
    }

    [BurstCompile]
    public unsafe void OnUpdate(ref SystemState state){
        if (Input.GetKey(KeyCode.Space))
            return;

        state.EntityManager.CompleteDependencyBeforeRW<LocalTransform>();
        speedHandle.Update(ref state);
        transformHandle.Update(ref state);
        var chunks = query.ToArchetypeChunkArray(state.WorldUpdateAllocator);
        foreach (var chunk in chunks){
            var count = chunk.Count;
            var speedPtr = chunk.GetComponentDataPtrRO(ref speedHandle);
            var transformPtr = chunk.GetComponentDataPtrRW(ref transformHandle);
            odecs_calls.Rotate(count, transformPtr, speedPtr, (TimeData*)UnsafeUtility.AddressOf(ref state.WorldUnmanaged.Time));
        }
    }

    public void OnDestroy(ref SystemState state) {
        odecs_calls.unload_calls();
    }
}