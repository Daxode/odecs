package odecs

import "core:log"
import "core:c"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:runtime"
import "core:strconv"
import "core:strings"
import "core:os"
import "core:intrinsics"
import "core:fmt"
import "core:dynlib"

ENABLE_UNITY_COLLECTIONS_CHECKS :: #config(ENABLE_UNITY_COLLECTIONS_CHECKS, true)
UNITY_DOTS_DEBUG :: #config(UNITY_DOTS_DEBUG, false)
odecs_context: runtime.Context

functions_that_call_unity :: struct #packed {
    odecs_context: ^runtime.Context,
    ToArchetypeChunkArray: proc "cdecl" (queryImpl: ^EntityQueryImpl, #by_ptr allocator: AllocatorManager_AllocatorHandle, array: ^NativeArray(ArchetypeChunk)),
    GetASHForComponent: proc "cdecl" (state: ^SystemState, typeIndex: ^TypeIndex, isReadOnly: u8, ash: ^AtomicSafetyHandle)
}

LookupCache :: struct #align(8)
{
    Archetype: ^Archetype,
    ComponentOffset: i32,
    ComponentSizeOf: u16,
    IndexInArchetype: i16,
}

when ENABLE_UNITY_COLLECTIONS_CHECKS {
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
        m_Safety: AtomicSafetyHandle
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


AccessMode :: enum
{
    ReadWrite,
    ReadOnly,
    Exclude
}

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
    MatchingQueryData: UnsafeList(rawptr), // UnsafeList<EntityQueryData*>
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
    Allocator: AllocatorManager_AllocatorHandle,
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
    m_UnmanagedSharedComponentsByType: UnsafeList(ComponentTypeList), // UnsafeList`1
    m_UnmanagedSharedComponentTypes: UnsafeList(TypeIndex), // UnsafeList`1
    m_UnmanagedSharedComponentInfo: UnsafeList(UnsafeList(SharedComponentInfo)), // UnsafeList`1
    m_HashLookup: UnsafeParallelMultiHashMap(u64, i32), // UnsafeParallelMultiHashMap`2
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

NativeArray :: struct($T: typeid) #packed where ENABLE_UNITY_COLLECTIONS_CHECKS {
    m_Buffer : [^]T,
    m_Length : i32,
    m_MinIndex, m_MaxIndex: i32,
    m_Safety: AtomicSafetyHandle,
    m_AllocatorLabel: Allocator
}

Allocator :: enum u32 {
    Invalid = 0,
    None = 1,
    Temp = 2,
    TempJob = 3,
    Persistent = 4,
    AudioKernel = 5,
    FirstUserIndex = 64
}

AtomicSafetyHandle :: struct #packed {
    versionNode: rawptr,
    version: i32,
    staticSafetyId: i32,
}

ProfilerMarker :: distinct rawptr

SystemState :: struct #align(4)
{
    m_SystemPtr: rawptr,
    m_JobHandle: JobHandle,
    m_Flags: u64,
    m_DependencyManager: rawptr,
    m_EntityComponentStore: ^EntityComponentStore,
    m_LastSystemVersion: u64,
    m_ProfilerMarker, m_ProfilerMarkerBurst: ProfilerMarker,
    m_Self: rawptr,
    m_SystemTypeIndex: SystemTypeIndex,
    m_SystemID: i32,
    m_EntityManager: EntityManager,
    m_JobDependencyForReadingSystems: UnsafeList(TypeIndex),
    m_JobDependencyForWritingSystems: UnsafeList(TypeIndex),
    m_EntityQueries: UnsafeList(EntityQuery),
    m_RequiredEntityQueries: UnsafeList(EntityQuery),
    m_WorldUnmanaged: WorldUnmanaged,
    m_Handle: SystemHandle,
    m_UnmanagedMetaIndex: i64,
    m_World: rawptr,
    m_ManagedSystem: rawptr,
    m_DebugName: NativeText_ReadOnly,
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
    m_Safety: AtomicSafetyHandle,
    m_IsInExclusiveTransaction: b64,
    m_EntityDataAccess: rawptr
}

WorldUnmanaged :: struct #packed
{
    m_Safety: AtomicSafetyHandle,
    m_Impl: ^WorldUnmanagedImpl,
}

WorldUnmanagedImpl :: struct #packed
{
    m_WorldAllocatorHelper: AllocatorHelper(AutoFreeAllocator),
    m_SystemStatePtrMap: NativeParallelHashMap(i32, rawptr),
    _stateMemory: StateAllocator,
    _unmanagedSlotByTypeHash: UnsafeParallelMultiHashMap(i64, u16),
    sysHandlesInCreationOrder: UnsafeList(PerWorldSystemInfo),
    SequenceNumber: u64,
    Flags: WorldFlags,
    CurrentTime: TimeData,
    Name: FixedString128Bytes,
    ExecutingSystem: SystemHandle,
    DoubleUpdateAllocators: ^DoubleRewindableAllocators,
    GroupUpdateAllocators: ^DoubleRewindableAllocators,
    m_EntityManager: EntityManager,
    MaximumDeltaTime: f32,
    
    m_AllowGetSystem: b8WhenCollectionChecks
}
b8WhenCollectionChecks :: b8 when ENABLE_UNITY_COLLECTIONS_CHECKS else struct{}

StateAllocator :: struct #packed
{
    m_FreeBits: u64,
    m_Level1: rawptr // StateAllocLevel1*
}

AllocatorHelper :: struct($T: typeid)
{
    m_allocator: ^T,
    m_backingAllocator: AllocatorManager_AllocatorHandle
}

AutoFreeAllocator :: struct #packed
{
    m_allocated, m_tofree: ArrayOfArrays(rawptr),
    m_handle: AllocatorManager_AllocatorHandle,
    m_backingAllocatorHandle: AllocatorManager_AllocatorHandle
}

ArrayOfArrays :: struct($T: typeid) #packed
{
    m_backingAllocatorHandle: AllocatorManager_AllocatorHandle,
    m_lengthInElements: i32,
    m_capacityInElements: i32,
    m_log2BlockSizeInElements: i32,
    m_blocks: i32,
    m_block: ^rawptr,
}

UnsafeParallelMultiHashMap :: struct($TKey, $TValue: typeid)
{
    m_Buffer: rawptr, // UnsafeParallelHashMapData*
    m_AllocatorLabel: AllocatorManager_AllocatorHandle
}

UnsafeParallelHashMap :: struct($TKey, $TValue: typeid)
{
    m_Buffer: rawptr, // UnsafeParallelHashMapData*
    m_AllocatorLabel: AllocatorManager_AllocatorHandle
}

NativeParallelHashMap :: struct($TKey, $TValue: typeid)
{
    m_HashMapData: UnsafeParallelHashMap(TKey, TValue),
    m_Safety: AtomicSafetyHandle
}

PerWorldSystemInfo :: struct #packed
{
    handle: SystemHandle,
    systemTypeIndex: i32
}
DoubleRewindableAllocators :: struct #packed
{
    Pointer: ^RewindableAllocator,
    UpdateAllocatorHelper: [2]AllocatorHelper(RewindableAllocator)
}

Union :: distinct i64
MemoryBlock :: struct #packed
{
    m_pointer:^u8,
    // how many bytes of contiguous memory it points to
    m_bytes: i64,
    m_union: Union
}
Spinner :: distinct i32
UnmanagedArray :: struct($T: typeid) #packed
{
    m_pointer: ^T,
    m_length: i32,
    m_allocator: AllocatorManager_AllocatorHandle
}
RewindableAllocator :: struct #packed
{
    m_spinner: Spinner,
    m_handle: AllocatorManager_AllocatorHandle,
    m_block: UnmanagedArray(MemoryBlock),
    m_last: i32,
    m_used: i32,
    m_enableBlockFree: b8,
    m_reachMaxBlockSize: b8,
}
ToAllocator :: proc {ToAllocatorRewindableAllocator, ToAllocatorAllocatorManager_AllocatorHandle}

ToAllocatorRewindableAllocator :: proc "contextless" (allocatorHandle: RewindableAllocator) -> Allocator 
{
    return ToAllocator(allocatorHandle.m_handle)
}

FixedString128Bytes :: struct #packed
{
    utf8LengthInBytes: u16,
    bytes: FixedBytes126
}
FixedBytes126 :: [126]u8
FixedBytes16 :: [16]u8
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
    __safety: AtomicSafetyHandle,
    __impl: ^EntityQueryImpl,
    __seqno: u64,
}

EntityQueryImpl :: distinct rawptr // TODO: MAKE ACTUAL DON"T USE TYPE

UnsafeList :: struct($T: typeid) #packed
{
    Ptr: [^]T,
    m_length: i32,
    m_capacity: i32,
    Allocator: AllocatorManager_AllocatorHandle,
    padding: i32
}

AllocatorManager_AllocatorHandle :: struct #packed
{
    Index, Version: u16
}
ToAllocatorAllocatorManager_AllocatorHandle :: proc "contextless" (allocatorHandle: AllocatorManager_AllocatorHandle) -> Allocator 
{
    lo := allocatorHandle.Index;
    hi := allocatorHandle.Version;
    value := (u32(hi) << 16) | u32(lo);
    return Allocator(value);
}

NativeText_ReadOnly :: struct #packed
{
    m_Data: rawptr,
    m_Safety: AtomicSafetyHandle,
}

JobHandle :: struct #packed
{
    jobGroup: u64,
    version: i32,
    debugVersion: i32,
    debugInfo: rawptr,
}

unity_funcs: functions_that_call_unity
@export
init :: proc "c" (funcs_that_call_unity: ^functions_that_call_unity) {
    unity_funcs = funcs_that_call_unity^
    odecs_context = unity_funcs.odecs_context^
    context = odecs_context
    log.debug("Odecs has initialized succesfully")
}

LocalTransform :: struct
{
    Position : [3]f32,
    Scale : f32,
    Rotation : quaternion128
}

TimeData :: struct
{
    ElapsedTime : f64,
    DeltaTime : c.float
}

SpinSpeed :: struct {
    radiansPerSecond : c.float
}

GetWorldUpdateAllocator :: proc "contextless" (state: ^SystemState) -> AllocatorManager_AllocatorHandle
{
    return state.m_WorldUnmanaged.m_Impl.DoubleUpdateAllocators.Pointer.m_handle
}

Update :: proc (handle: ^ComponentTypeHandle($T), state: ^SystemState) 
{
    when ENABLE_UNITY_COLLECTIONS_CHECKS {
        unity_funcs.GetASHForComponent(state, &handle.m_TypeIndex, u8(handle.m_IsReadOnly), &handle.m_Safety)
    }
    handle.m_GlobalSystemVersion = state.m_EntityComponentStore.m_GlobalSystemVersion
}

ToArchetypeChunkArray :: proc "contextless" (query: ^EntityQuery, allocator: AllocatorManager_AllocatorHandle) -> []ArchetypeChunk {
    chunks: NativeArray(ArchetypeChunk)
    unity_funcs.ToArchetypeChunkArray(query.__impl, allocator, &chunks)
    return chunks.m_Buffer[:chunks.m_Length]
}

@export
Rotate :: proc "c" (state: ^SystemState, query: ^EntityQuery, transform_handle: ^ComponentTypeHandle(LocalTransform), spinspeed_handle: ^ComponentTypeHandle(SpinSpeed))
{
    context = odecs_context
    time := state.m_WorldUnmanaged.m_Impl.CurrentTime;
    Update(transform_handle, state)
    Update(spinspeed_handle, state)
    
    chunks := ToArchetypeChunkArray(query, GetWorldUpdateAllocator(state))
    for &chunk in chunks {
        transforms := Chunk_GetComponentDataRW(&chunk, transform_handle)
        spinspeeds := Chunk_GetComponentDataRO(&chunk, spinspeed_handle)
        for &transform, i in transforms
        {
            transform.Rotation *= RotateY(time.DeltaTime * spinspeeds[i].radiansPerSecond);
            transform.Position.y = math.sin(f32(time.ElapsedTime));
        }
    }
} 

RotateY :: proc "contextless" (angle: f32) -> quaternion128
{
    sina, cosa := math.sincos(0.5 * angle);
    return quaternion(sina, 0.0, cosa, 0.0);
}

main :: proc() {
    fmt.println(align_of(EntityComponentStore), size_of(EntityComponentStore))
}


Chunk_GetComponentDataRW :: proc (archChunk: ^ArchetypeChunk, typeHandle: ^ComponentTypeHandle($T)) -> []T {
    return (transmute([^]T)ChunkDataUtility_GetOptionalComponentDataWithTypeRW(archChunk.m_Chunk, archChunk.m_Chunk.Archetype,
        0, typeHandle.m_TypeIndex,
        typeHandle.m_GlobalSystemVersion, &typeHandle.m_LookupCache))[:archChunk.m_Chunk.Count];
}

ChunkDataUtility_GetOptionalComponentDataWithTypeRW :: proc(chunk: ^Chunk, archetype: ^Archetype, baseEntityIndex: i32, typeIndex: TypeIndex, globalSystemVersion: u32, lookupCache: ^LookupCache) -> [^]u8
{
    if (lookupCache.Archetype != archetype) {
        LookupCache_Update(lookupCache, archetype, typeIndex);
    }
    if (lookupCache.IndexInArchetype == -1){
        return nil;
    }

    // Write Component to Chunk. ChangeVersion:Yes OrderVersion:No
    Chunk_SetChangeVersion(chunk, i32(lookupCache.IndexInArchetype), globalSystemVersion);
    return &(transmute([^]u8)chunk)[64 + lookupCache.ComponentOffset + i32(lookupCache.ComponentSizeOf) * baseEntityIndex];
}

Chunk_GetComponentDataRO :: proc (archChunk: ^ArchetypeChunk, typeHandle: ^ComponentTypeHandle($T)) -> []T {
    return (transmute([^]T)ChunkDataUtility_GetOptionalComponentDataWithTypeRO(archChunk.m_Chunk, archChunk.m_Chunk.Archetype,
        0, typeHandle.m_TypeIndex,
        typeHandle.m_GlobalSystemVersion, &typeHandle.m_LookupCache))[:archChunk.m_Chunk.Count];
}

ChunkDataUtility_GetOptionalComponentDataWithTypeRO :: proc(chunk: ^Chunk, archetype: ^Archetype, baseEntityIndex: i32, typeIndex: TypeIndex, globalSystemVersion: u32, lookupCache: ^LookupCache) -> [^]u8
{
    if (lookupCache.Archetype != archetype){
        LookupCache_Update(lookupCache, archetype, typeIndex);
    }
    if (lookupCache.IndexInArchetype == -1){
        return nil;
    }
    
    return &(transmute([^]u8)chunk)[64 + lookupCache.ComponentOffset + i32(lookupCache.ComponentSizeOf) * baseEntityIndex];
}

Chunk_SetChangeVersion :: proc (using self: ^Chunk, indexInArchetype: i32, version: u32)
{
    Chunks_SetChangeVersion(&Archetype.Chunks, indexInArchetype, ListIndex, version);
}

Chunks_SetChangeVersion :: proc (using self: ^ArchetypeChunkData, indexInArchetype: i32, chunkIndex: i32, version: u32)
{
    changeVersions := GetChangeVersionArrayForType(self, indexInArchetype);
    changeVersions[chunkIndex] = version;
}

GetChangeVersionArrayForType :: proc (using self: ^ArchetypeChunkData, indexInArchetype: i32) -> [^]u32
{
    when ENABLE_UNITY_COLLECTIONS_CHECKS || UNITY_DOTS_DEBUG {
        assert(indexInArchetype >= 0 && indexInArchetype < ComponentCount,
            "out-of-range indexInArchetype passed to GetChangeVersionArrayForType");
    }

    changeVersions := &p[Capacity];
    return &(transmute([^]u32)changeVersions)[indexInArchetype * Capacity];
}


LookupCache_Update :: proc(using cache: ^LookupCache, archetype: ^Archetype, typeIndex: TypeIndex)
{
    GetIndexInTypeArray(archetype, typeIndex, &IndexInArchetype);
    ComponentOffset = IndexInArchetype == -1 ? 0 : archetype.Offsets[IndexInArchetype];
    ComponentSizeOf = IndexInArchetype == -1 ? u16(0) : archetype.SizeOfs[IndexInArchetype];
    Archetype = archetype;
}

GetIndexInTypeArray :: proc (archetype: ^Archetype, typeIndex: TypeIndex, typeLookupCache: ^i16)
{
    types := archetype.Types;
    typeCount := archetype.TypesCount;

    if (typeLookupCache^ >= 0 
        && typeLookupCache^ < i16(typeCount) 
        && types[typeLookupCache^].TypeIndex == typeIndex) {
        return;
    }

    for type, i in types[:typeCount]
    {
        if (typeIndex != type.TypeIndex) {
            continue;
        }

        typeLookupCache^ = i16(i);
        return;
    }

    typeLookupCache^ = i16(-1);
}