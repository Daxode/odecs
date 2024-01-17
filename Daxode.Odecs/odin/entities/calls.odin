package odecs_entities

import "core:log"

import "../collections"
import "core:runtime"

unity_funcs: functions_that_call_unity
functions_that_call_unity :: struct #packed {
    odecs_context: ^runtime.Context,
    ToArchetypeChunkArray: proc "cdecl" (queryImpl: ^EntityQueryImpl, #by_ptr allocator: collections.AllocatorManager_AllocatorHandle, array: ^collections.NativeArray(ArchetypeChunk)),
    GetASHForComponent: proc "cdecl" (state: ^SystemState, typeIndex: ^TypeIndex, isReadOnly: u8, ash: ^collections.AtomicSafetyHandle)
}

GetWorldUpdateAllocator :: proc "contextless" (state: ^SystemState) -> collections.AllocatorManager_AllocatorHandle
{
    return state.m_WorldUnmanaged.m_Impl.DoubleUpdateAllocators.Pointer.m_handle
}

Update :: proc {ComponentTypeHandle_Update}

ComponentTypeHandle_Update :: proc (handle: ^ComponentTypeHandle($T), state: ^SystemState) 
{
    when collections.ENABLE_UNITY_COLLECTIONS_CHECKS {
        unity_funcs.GetASHForComponent(state, &handle.m_TypeIndex, u8(handle.m_IsReadOnly), &handle.m_Safety)
    }
    handle.m_GlobalSystemVersion = state.m_EntityComponentStore.m_GlobalSystemVersion
}

ToArchetypeChunkArray :: proc "contextless" (query: ^EntityQuery, allocator: collections.AllocatorManager_AllocatorHandle) -> []ArchetypeChunk {
    chunks: collections.NativeArray(ArchetypeChunk)
    unity_funcs.ToArchetypeChunkArray(query.__impl, allocator, &chunks)
    return chunks.m_Buffer[:chunks.m_Length]
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
    when collections.ENABLE_UNITY_COLLECTIONS_CHECKS || collections.UNITY_DOTS_DEBUG {
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

