package odecs_entities

import "../collections"

TimeData :: struct
{
    ElapsedTime : f64,
    DeltaTime : f32
}

LookupCache :: struct #align(8)
{
    Archetype: ^Archetype,
    ComponentOffset: i32,
    ComponentSizeOf: u16,
    IndexInArchetype: i16,
}

when collections.ENABLE_UNITY_COLLECTIONS_CHECKS {
    ComponentTypeHandleRaw :: struct #align(8)
    {
        m_LookupCache: LookupCache,
        m_TypeIndex: TypeIndex,
        m_SizeInChunk: i32,
        m_GlobalSystemVersion: u32,
        m_IsReadOnly: b8,
        m_IsZeroSized: b8,
        _: [2]u8,
        m_Length: i32,
        m_MinIndex, m_MaxIndex: i32,
        m_Safety: collections.AtomicSafetyHandle
    }
} else {
    ComponentTypeHandleRaw :: struct #align(8)
    {
        m_LookupCache: LookupCache,
        m_TypeIndex: TypeIndex,
        m_SizeInChunk: i32,
        m_GlobalSystemVersion: u32,
        m_IsReadOnly: b8,
        m_IsZeroSized: b8,
        _: [2]u8,
        m_Length: i32,
    }
}

ComponentTypeHandle :: struct($T: typeid) {
    using val: ComponentTypeHandleRaw
}

TypeIndex :: distinct i32
SystemTypeIndex :: distinct i32

ArchetypeChunk :: struct #packed {
    m_Chunk: ^Chunk,
    m_EntityComponentStore: ^EntityComponentStore
}

Entity :: struct #packed {
    identifier, version: i32
}

Chunk :: struct #align(8) {
    Archetype: ^Archetype,
    metaChunkEntity: Entity,
    Count: i32,
    Capacity: i32,
    ListIndex: i32,
    ListWithEmptySlotsIndex: i32,
    Flags: u32,
    ChunkstoreIndex: i32,
    SequenceNumber: u64,
    Buffer: [8]u8, // <Buffer>e__FixedBuffer
} // total: 72

ComponentTypeInArchetype :: struct #align(4)
{
    TypeIndex: TypeIndex, // TypeIndex
} // total: 4

ArchetypeChunkData :: struct #align(8)
{
    p: [^]^Chunk, // Chunk**
    Capacity: i32, // Int32
    Count: i32, // Int32
    SharedComponentCount: i32, // Int32
    ComponentCount: i32, // Int32
} // total: 24


Archetype :: struct #align(8)
{
    Chunks: ArchetypeChunkData, // ArchetypeChunkData
    ChunksWithEmptySlots: [3]u64, // UnsafePtrList`1
    FreeChunksBySharedComponents: [7]u64, // ChunkListMap
    Types: [^]ComponentTypeInArchetype, // ComponentTypeInArchetype*
    EnableableTypeIndexInArchetype: ^i32, // Int32*
    MatchingQueryData: collections.UnsafeList(rawptr), // UnsafeList<EntityQueryData*>
    NextChangedArchetype: ^Archetype, // Archetype*
    EntityCount: i32, // Int32
    ChunkCapacity: i32, // Int32
    TypesCount: i32, // Int32
    EnableableTypesCount: i32, // Int32
    InstanceSize: i32, // Int32
    InstanceSizeWithOverhead: i32, // Int32
    ScalarEntityPatchCount: i32, // Int32
    BufferEntityPatchCount: i32, // Int32
    StableHash: u64, // UInt64
    TypeMemoryOrderIndexToIndexInArchetype: ^i32, // Int32*
    TypeIndexInArchetypeToMemoryOrderIndex: ^i32, // Int32*
    Offsets: [^]i32, // Int32*
    SizeOfs: [^]u16, // UInt16*
    BufferCapacities: [^]i32, // Int32*
    FirstBufferComponent: i16, // Int16
    FirstManagedComponent: i16, // Int16
    FirstTagComponent: i16, // Int16
    FirstSharedComponent: i16, // Int16
    FirstChunkComponent: i16, // Int16
    Flags: [1]u32, // ArchetypeFlags
    CopyArchetype: ^Archetype, // Archetype*
    InstantiateArchetype: ^Archetype, // Archetype*
    CleanupResidueArchetype: ^Archetype, // Archetype*
    MetaChunkArchetype: ^Archetype, // Archetype*
    ScalarEntityPatches: rawptr, // EntityPatchInfo*
    BufferEntityPatches: rawptr, // BufferEntityPatchInfo*
    EntityComponentStore: ^EntityComponentStore, // EntityComponentStore*
    QueryMaskArray: [16]u64, // <QueryMaskArray>e__FixedBuffer
} // total: 432


ComponentType :: struct {
    TypeIndex: TypeIndex,
    AccessModeType: AccessMode
}

AccessMode :: enum
{
    ReadWrite,
    ReadOnly,
    Exclude
}

SharedComponentInfo :: struct 
{
    RefCount: i32,
    ComponentType: i32,
    Version: i32,
    HashCode: i32,
}

ComponentTypeList :: struct
{
    Ptr: rawptr,
    Length: i32,
    Capacity: i32,
    Allocator: collections.AllocatorManager_AllocatorHandle,
}

EntityComponentStore :: struct #align(8)
{
    m_VersionByEntity: ^i32, // Int32*
    m_ArchetypeByEntity: ^^Archetype, // Archetype**
    m_EntityInChunkByEntity: rawptr, // EntityInChunk*
    m_ComponentTypeOrderVersion: ^i32, // Int32*
    m_ArchetypeChunkAllocator: [12]u64, // BlockAllocator
    m_Archetypes: [3]u64, // UnsafePtrList`1
    m_TypeLookup: [7]u64, // ArchetypeListMap
    m_ManagedComponentIndex: i32, // Int32
    m_ManagedComponentIndexCapacity: i32, // Int32
    m_ManagedComponentFreeIndex: [3]u64, // UnsafeAppendBuffer
    ManagedChangesTracker: [4]u64, // ManagedDeferredCommands
    m_SharedComponentVersion: i32, // Int32
    m_SharedComponentGlobalVersion: i32, // Int32
    m_UnmanagedSharedComponentCount: i32, // Int32
    _: [4]u8,
    m_UnmanagedSharedComponentsByType: collections.UnsafeList(ComponentTypeList), // UnsafeList`1
    m_UnmanagedSharedComponentTypes: collections.UnsafeList(TypeIndex), // UnsafeList`1
    m_UnmanagedSharedComponentInfo: collections.UnsafeList(collections.UnsafeList(SharedComponentInfo)), // UnsafeList`1
    m_HashLookup: collections.UnsafeParallelMultiHashMap(u64, i32), // UnsafeParallelMultiHashMap`2
    m_ChunkListChangesTracker: u64, // ChunkListChanges
    m_WorldSequenceNumber: u64, // UInt64
    m_NextChunkSequenceNumber: u64, // UInt64
    m_NextFreeEntityIndex: i32, // Int32
    m_EntityCreateDestroyVersion: i32, // Int32
    m_GlobalSystemVersion: u32, // UInt32
    m_EntitiesCapacity: i32, // Int32
    m_IntentionallyInconsistent: i32, // Int32
    m_ArchetypeTrackingVersion: u32, // UInt32
    m_LinkedGroupType: TypeIndex, // TypeIndex
    m_ChunkHeaderType: TypeIndex, // TypeIndex
    m_PrefabType: TypeIndex, // TypeIndex
    m_CleanupEntityType: TypeIndex, // TypeIndex
    m_DisabledType: TypeIndex, // TypeIndex
    m_EntityType: TypeIndex, // TypeIndex
    m_SystemInstanceType: TypeIndex, // TypeIndex
    m_ChunkHeaderComponentType: ComponentType, // ComponentType
    m_EntityComponentType: ComponentType, // ComponentType
    m_SimulateComponentType: ComponentType, // ComponentType
    m_TypeInfos: rawptr, // TypeInfo*
    m_EntityOffsetInfos: rawptr, // EntityOffsetInfo*
    m_DebugOnlyManagedAccess: i32, // Int32
    memoryInitPattern: b8, // Byte
    useMemoryInitPattern: b8, // Byte
    m_RecordToJournal: b8, // Byte
    _: [1]u8,
    m_StructuralChangesRecorder: rawptr, // Recorder*
    m_NameByEntity: ^EntityName, // EntityName*
    m_NameChangeBitsSequenceNum: u64, // UInt64
    m_NameChangeBitsByEntity: [3]u64, // UnsafeBitArray
} // total: 552

EntityName :: distinct i32

WorldFlag :: enum {
    Live       = 0,
    Editor     = 1,
    Game       = 2,
    Simulation = 3,
    Conversion = 4,
    Staging    = 5,
    Shadow     = 6,
    Streaming  = 7,
    GameServer = 8,
    GameClient = 9,
    GameThinClient = 10,
}
WorldFlags :: bit_set[WorldFlag; u64]

EntityQuery :: struct #packed
{
    __safety: collections.AtomicSafetyHandle,
    __impl: ^EntityQueryImpl,
    __seqno: u64,
}

EntityQueryImpl :: distinct rawptr // TODO: MAKE ACTUAL DON"T USE TYPE

SystemState :: struct #align(4)
{
    m_SystemPtr: rawptr,
    m_JobHandle: collections.JobHandle,
    m_Flags: u64,
    m_DependencyManager: rawptr,
    m_EntityComponentStore: ^EntityComponentStore,
    m_LastSystemVersion: u64,
    m_ProfilerMarker, m_ProfilerMarkerBurst: collections.ProfilerMarker,
    m_Self: rawptr,
    m_SystemTypeIndex: SystemTypeIndex,
    m_SystemID: i32,
    m_EntityManager: EntityManager,
    m_JobDependencyForReadingSystems: collections.UnsafeList(TypeIndex),
    m_JobDependencyForWritingSystems: collections.UnsafeList(TypeIndex),
    m_EntityQueries: collections.UnsafeList(EntityQuery),
    m_RequiredEntityQueries: collections.UnsafeList(EntityQuery),
    m_WorldUnmanaged: WorldUnmanaged,
    m_Handle: SystemHandle,
    m_UnmanagedMetaIndex: i64,
    m_World: rawptr,
    m_ManagedSystem: rawptr,
    m_DebugName: collections.NativeText_ReadOnly,
}

SystemHandle :: struct #packed
{
    m_Entity: Entity,
    m_Handle: u16,
    m_Version: u16,
    m_WorldSeqNo: u32,
}

EntityManager :: struct #packed
{
    m_Safety: collections.AtomicSafetyHandle,
    m_IsInExclusiveTransaction: b64,
    m_EntityDataAccess: rawptr
}

WorldUnmanaged :: struct #packed
{
    m_Safety: collections.AtomicSafetyHandle,
    m_Impl: ^WorldUnmanagedImpl,
}

WorldUnmanagedImpl :: struct #packed
{
    m_WorldAllocatorHelper: collections.AllocatorHelper(collections.AutoFreeAllocator),
    m_SystemStatePtrMap: collections.NativeParallelHashMap(i32, rawptr),
    _stateMemory: collections.StateAllocator,
    _unmanagedSlotByTypeHash: collections.UnsafeParallelMultiHashMap(i64, u16),
    sysHandlesInCreationOrder: collections.UnsafeList(PerWorldSystemInfo),
    SequenceNumber: u64,
    Flags: WorldFlags,
    CurrentTime: TimeData,
    Name: collections.FixedString128Bytes,
    ExecutingSystem: SystemHandle,
    DoubleUpdateAllocators: ^collections.DoubleRewindableAllocators,
    GroupUpdateAllocators: ^collections.DoubleRewindableAllocators,
    m_EntityManager: EntityManager,
    MaximumDeltaTime: f32,
    
    m_AllowGetSystem: b8WhenCollectionChecks
}
b8WhenCollectionChecks :: b8 when collections.ENABLE_UNITY_COLLECTIONS_CHECKS else struct{}

PerWorldSystemInfo :: struct #packed
{
    handle: SystemHandle,
    systemTypeIndex: i32
}