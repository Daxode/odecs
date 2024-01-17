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
using Unity.Burst.CompilerServices;
using System.Reflection;

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
        IntPtr entityQueryToArchetypeChunkArray;
        IntPtr getASHForComponent;
        public void Init() {
            debugLog = BurstCompiler.CompileFunctionPointer<DebugLog>(Log).Value;
            entityQueryToArchetypeChunkArray = BurstCompiler.CompileFunctionPointer<ToArchetypeChunkArrayFunc>(ToArchetypeChunkArray).Value;
            getASHForComponent = BurstCompiler.CompileFunctionPointer<GetASHForComponentFunc>(GetASHForComponent).Value;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct ComponentTypeHandleRaw
        {
            public LookupCache m_LookupCache;
            public TypeIndex m_TypeIndex;
            public int m_SizeInChunk;
            public uint m_GlobalSystemVersion;
            public byte m_IsReadOnly;
            public byte m_IsZeroSized;
            public int m_Length;
            public int m_MinIndex; 
            public int m_MaxIndex;
            public AtomicSafetyHandle m_Safety;
            public readonly bool IsReadOnly => m_IsReadOnly == 1;
        }


        static void JournalAddRecordGetComponentDataRW(ArchetypeChunk* archetypeChunk, ComponentTypeHandleRaw* typeHandle, void* data, int dataLength){
                EntitiesJournaling.AddRecord(
                    recordType: EntitiesJournaling.RecordType.GetComponentDataRW,
                    entityComponentStore: archetypeChunk->m_EntityComponentStore,
                    globalSystemVersion: typeHandle->m_GlobalSystemVersion,
                    chunks: archetypeChunk,
                    chunkCount: 1,
                    types: (TypeIndex*)UnsafeUtility.AddressOf(ref typeHandle->m_TypeIndex),
                    typeCount: 1,
                    data: data,
                    dataLength: dataLength);
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

        // Debug.Log
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
    public unsafe static void  Init()
    {
        s_functionsToCallFromOdin.Init();
        init(UnsafeUtility.AddressOf(ref s_functionsToCallFromOdin));
    }

    [DllImport("odecs")]
    static extern void init(void* ptr);

    public static delegate* unmanaged[Cdecl]<ref SystemState, ref EntityQuery, void*, void*, void> Rotate 
            => (delegate* unmanaged[Cdecl]<ref SystemState, ref EntityQuery, void*, void*, void>) data.Data.Rotate;
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
        odecs_calls.Init();
        speedHandle = SystemAPI.GetComponentTypeHandle<SpinSpeed>(true);
        transformHandle = SystemAPI.GetComponentTypeHandle<LocalTransform>();
        query = SystemAPI.QueryBuilder().WithAll<SpinSpeed, LocalTransform>().Build();
    }

    [BurstCompile]
    public unsafe void OnUpdate(ref SystemState state){
        if (Input.GetKey(KeyCode.Space))
            return;

        state.EntityManager.CompleteDependencyBeforeRW<LocalTransform>();
        // PrintFieldOfType<AtomicSafetyHandle>();
        // PrintFieldOfType<ArchetypeChunkData>();

        odecs_calls.Rotate(
            ref state, ref query,
            UnsafeUtility.AddressOf(ref transformHandle), 
            UnsafeUtility.AddressOf(ref speedHandle));
    }

    public void OnDestroy(ref SystemState state) {
        odecs_calls.unload_calls();
    }

    static unsafe void PrintFieldOfType<T>() where T : unmanaged
    {
        var stringBuilder = new System.Text.StringBuilder();
        var alignment = UnsafeUtility.AlignOf<T>();
        stringBuilder.AppendLine($"{typeof(T).Name} :: struct #align({alignment})");
        stringBuilder.AppendLine("{");
        var fieldEnumerator = typeof(T)
            .GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic).GetEnumerator();
        fieldEnumerator.MoveNext();
        var field = (FieldInfo)fieldEnumerator.Current;
        var previousOffset = UnsafeUtility.GetFieldOffset(field);
        var previousName = field.Name;
        var previousType = field.FieldType.Name;
        while (fieldEnumerator.MoveNext())
        {
            field = (FieldInfo)fieldEnumerator.Current;
            var currentOffset = UnsafeUtility.GetFieldOffset(field);
            stringBuilder.AppendLine($"    {previousName}: {ReturnHighestForCurrentAlignment(alignment, currentOffset-previousOffset)}, // {previousType}");
            previousOffset = currentOffset;
            previousName = field.Name;
            previousType = field.FieldType.Name;
        }
        stringBuilder.AppendLine($"    {previousName}: {ReturnHighestForCurrentAlignment(alignment, UnsafeUtility.SizeOf<T>()-previousOffset)}, // {previousType}");
        stringBuilder.AppendLine($"}} // total: {UnsafeUtility.SizeOf<T>()}");
        Debug.Log(stringBuilder.ToString());
    }

    static string ReturnHighestForCurrentAlignment(int alignment, int bytes){
        if (bytes/8 > 0 && alignment >= 8){
            return $"[{bytes/8}]u64";
        } else if (bytes/4 > 0 && alignment >= 4){
            return $"[{bytes/4}]u32";
        } else if (bytes/2 > 0 && alignment >= 2){
            return $"[{bytes/2}]u16";
        } else {
            return $"[{bytes}]u8";
        }
    }
}