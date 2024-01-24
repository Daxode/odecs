using Unity.Burst;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Entities;
using Unity.Mathematics;
using Unity.Transforms;
using UnityEngine;
using System.Reflection;
using System;
using System.Runtime.InteropServices;
using Unity.Jobs.LowLevel.Unsafe;
using UnityEngine.Assertions;
using Unity.Collections;
using System.Linq;

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
partial struct odecs_setup_system : ISystem {
    ComponentTypeHandle<SpinSpeed> speedHandle;
    ComponentTypeHandle<LocalTransform> transformHandle;
    EntityQuery query;

    public unsafe void OnCreate(ref SystemState state){
        speedHandle = SystemAPI.GetComponentTypeHandle<SpinSpeed>(true);
        transformHandle = SystemAPI.GetComponentTypeHandle<LocalTransform>();
        query = SystemAPI.QueryBuilder().WithAll<SpinSpeed, LocalTransform>().Build();
    }

    void PrintStableTypeHash<T>() {
        var type = typeof(T);
        var memoryOrdering = TypeHash.CalculateMemoryOrdering(type, out var hasCustomMemoryOrder, null);
        // The stable type hash is the same as the memory order if the user hasn't provided a custom memory ordering
        var stableTypeHash = !hasCustomMemoryOrder ? memoryOrdering : TypeHash.CalculateStableTypeHash(type, null, null);
        Debug.Log($"{typeof(T).Name}'s stable hash: {stableTypeHash}");
        if (typeof(T).GetInterfaces().Any(v=>v.Name == "IComponentData"))
            Debug.Log($"{typeof(T).Name}'s typeindex: {TypeManager.GetTypeIndex<T>().Value}");
    }

    //[BurstCompile]
    public unsafe void OnUpdate(ref SystemState state){
        if (!odecs_calls.IsAvailable)
            return;

        state.EntityManager.CompleteDependencyBeforeRW<LocalTransform>();
        //PrintFieldOfType<UnsafeParallelHashMapData>();

        odecs_calls.Rotate(
            ref state, ref query,
            UnsafeUtility.AddressOf(ref transformHandle), 
            UnsafeUtility.AddressOf(ref speedHandle));
    }

    static unsafe void PrintFieldOfType(Type t)
    {
        var stringBuilder = new System.Text.StringBuilder();
        var alignment = 8;
        stringBuilder.AppendLine($"{t.Name} :: struct #align({alignment})");
        stringBuilder.AppendLine("{");
        var fieldEnumerator = t
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
        stringBuilder.AppendLine($"    {previousName}: {ReturnHighestForCurrentAlignment(alignment, UnsafeUtility.SizeOf(t)-previousOffset)}, // {previousType}");
        stringBuilder.AppendLine($"}} // total: {UnsafeUtility.SizeOf(t)}");
        Debug.Log(stringBuilder.ToString());
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

[StructLayout(LayoutKind.Explicit)]
internal unsafe struct UnsafeParallelHashMapData
{
    [FieldOffset(0)]
    internal byte* values;
    // 4-byte padding on 32-bit architectures here

    [FieldOffset(8)]
    internal byte* keys;
    // 4-byte padding on 32-bit architectures here

    [FieldOffset(16)]
    internal byte* next;
    // 4-byte padding on 32-bit architectures here

    [FieldOffset(24)]
    internal byte* buckets;
    // 4-byte padding on 32-bit architectures here

    [FieldOffset(32)]
    internal int keyCapacity;

    [FieldOffset(36)]
    internal int bucketCapacityMask; // = bucket capacity - 1

    [FieldOffset(40)]
    internal int allocatedIndexLength;

#if UNITY_2022_2_14F1_OR_NEWER
    const int kFirstFreeTLSOffset = JobsUtility.CacheLineSize < 64 ? 64 : JobsUtility.CacheLineSize;
    internal int* firstFreeTLS => (int*)((byte*)UnsafeUtility.AddressOf(ref this) + kFirstFreeTLSOffset);
#else
    [FieldOffset(JobsUtility.CacheLineSize < 64 ? 64 : JobsUtility.CacheLineSize)]
    internal fixed int firstFreeTLS[JobsUtility.MaxJobThreadCount * IntsPerCacheLine];
#endif
    internal const int IntsPerCacheLine = JobsUtility.CacheLineSize / sizeof(int);
}