using Unity.Burst;
using Unity.Collections.LowLevel.Unsafe;
using Unity.Entities;
using Unity.Mathematics;
using Unity.Transforms;
using UnityEngine;
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
partial struct odecs_setup_system : ISystem {
    ComponentTypeHandle<SpinSpeed> speedHandle;
    ComponentTypeHandle<LocalTransform> transformHandle;
    EntityQuery query;

    public unsafe void OnCreate(ref SystemState state){
        speedHandle = SystemAPI.GetComponentTypeHandle<SpinSpeed>(true);
        transformHandle = SystemAPI.GetComponentTypeHandle<LocalTransform>();
        query = SystemAPI.QueryBuilder().WithAll<SpinSpeed, LocalTransform>().Build();
    }

    [BurstCompile]
    public unsafe void OnUpdate(ref SystemState state){
        if (!odecs_calls.IsAvailable)
            return;

        state.EntityManager.CompleteDependencyBeforeRW<LocalTransform>();
        // PrintFieldOfType<AtomicSafetyHandle>();
        // PrintFieldOfType<ArchetypeChunkData>();

        odecs_calls.Rotate(
            ref state, ref query,
            UnsafeUtility.AddressOf(ref transformHandle), 
            UnsafeUtility.AddressOf(ref speedHandle));
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