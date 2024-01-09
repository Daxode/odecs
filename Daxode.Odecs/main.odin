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

odecs_context: runtime.Context

functions_that_call_unity :: struct #packed {
    debugLog: proc "cdecl" (str: cstring, len: int),
    GetComponentDataROPtr: GetComponentDataPtr(byte),
    GetComponentDataRWPtr: GetComponentDataPtr(byte),
}

GetComponentDataPtr :: struct($T: typeid) {
    func: proc "cdecl" (archChunk: ^ArchetypeChunk, typeHandle: ^ComponentTypeHandle(T)) -> [^]T
}

LookupCache :: struct #packed
{
    Archetype: rawptr,
    ComponentOffset: i32,
    ComponentSizeOf: u16,
    IndexInArchetype: i16,
}

ComponentTypeHandle :: struct($T: typeid) #packed
{
    m_LookupCache: LookupCache,
    m_TypeIndex: TypeIndex,
    m_SizeInChunk: i32,
    m_GlobalSystemVersion: u32,
    m_IsReadOnly: byte,
    m_IsZeroSized: byte,
}

TypeIndex :: distinct i32
SystemTypeIndex :: distinct i32

ArchetypeChunk :: struct #packed {
    m_Chunk: ^Chunk,
    m_EntityComponentStore: rawptr
}

Entity :: struct #packed {
    identifier, version: i32
}

Chunk :: struct #packed {
    Archetype: rawptr,
    metaChunkEntity: Entity,
    Count: i32,
    Capacity: i32,
    ListIndex: i32,
    ListWithEmptySlotsIndex: i32,
    Flags: u32,
    ChunkstoreIndex: i32,
    SequenceNumber: u64
}

COLLECTION_CHECKS :: true

NativeArray :: struct($T: typeid) #packed where COLLECTION_CHECKS {
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
    m_EntityComponentStore: rawptr,
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
b8WhenCollectionChecks :: b8 when COLLECTION_CHECKS else struct{}

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
    __impl: rawptr,
    __seqno: u64,
}

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
    odecs_context = runtime.default_context()
    odecs_context.logger = {
        options = {.Short_File_Path, .Line},
        procedure = proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
            my_test := strings.clone_to_cstring(text)
            unity_funcs.debugLog(my_test, len(my_test)+1)
        },
    }
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

GetComponentDataRWPtr :: proc (archChunk: ^ArchetypeChunk, typeHandle: ^ComponentTypeHandle($T)) -> []T
{
    return (transmute(GetComponentDataPtr(T))(unity_funcs.GetComponentDataRWPtr)).func(archChunk, typeHandle)[:archChunk.m_Chunk.Count]
}

GetComponentDataROPtr :: proc (archChunk: ^ArchetypeChunk, typeHandle: ^ComponentTypeHandle($T)) -> []T
{
    return (transmute(GetComponentDataPtr(T))(unity_funcs.GetComponentDataROPtr)).func(archChunk, typeHandle)[:archChunk.m_Chunk.Count]
}

GetWorldUpdateAllocator :: proc "contextless" (state: ^SystemState) -> Allocator
{
    return ToAllocator(state.m_WorldUnmanaged.m_Impl.DoubleUpdateAllocators.Pointer.m_handle)
}

@export
Rotate :: proc "c" (state: ^SystemState, world: ^WorldUnmanaged, alloc: ^RewindableAllocator, transform_handle: ^ComponentTypeHandle(LocalTransform), spinspeed_handle: ^ComponentTypeHandle(SpinSpeed), time: ^TimeData)
{
    context = odecs_context
    worldUpdateAllocator := GetWorldUpdateAllocator(state)
    log.debug(worldUpdateAllocator)
    
    // for &chunk in chunks.m_Buffer[:chunks.m_Length]{
    //     transforms := GetComponentDataRWPtr(&chunk, transform_handle)
    //     spinspeeds := GetComponentDataROPtr(&chunk, spinspeed_handle)
    //     for &transform, i in transforms
    //     {
    //         transform.Rotation *= RotateY(time.DeltaTime * spinspeeds[i].radiansPerSecond);
    //         transform.Position.y = math.sin(f32(time.ElapsedTime));
    //     }
    // }
}

RotateY :: proc "contextless" (angle: f32) -> quaternion128
{
    sina, cosa := math.sincos(0.5 * angle);
    return quaternion(sina, 0.0, cosa, 0.0);
}
