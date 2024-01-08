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
    ComponentOffset: int,
    ComponentSizeOf: u16,
    IndexInArchetype: i16,
}

ComponentTypeHandle :: struct($T: typeid) #packed
{
    m_LookupCache: LookupCache,
    m_TypeIndex: TypeIndex,
    m_SizeInChunk: int,
    m_GlobalSystemVersion: uint,
    m_IsReadOnly: byte,
    m_IsZeroSized: byte,
}

TypeIndex :: distinct int

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
    m_Length : int,
    m_MinIndex, m_MaxIndex: int,
    m_Safety: AtomicSafetyHandle,
    m_AllocatorLabel: Allocator
}

Allocator :: enum {
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
    version: int,
    staticSafetyId: int,
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

@export
Rotate :: proc "c" (chunks: ^NativeArray(ArchetypeChunk), transform_handle: ^ComponentTypeHandle(LocalTransform), spinspeed_handle: ^ComponentTypeHandle(SpinSpeed), time: ^TimeData)
{
    context = odecs_context
    for &chunk in chunks.m_Buffer[:chunks.m_Length]{
        transforms := GetComponentDataRWPtr(&chunk, transform_handle)
        spinspeeds := GetComponentDataROPtr(&chunk, spinspeed_handle)
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
