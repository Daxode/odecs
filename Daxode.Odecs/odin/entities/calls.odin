package odecs_entities

import "core:log"

import "../collections"
import "core:runtime"

unity_funcs: functions_that_call_unity
functions_that_call_unity :: struct #packed {
    odecs_context: ^runtime.Context,
    ToArchetypeChunkArray: proc "cdecl" (queryImpl: ^EntityQueryImpl, #by_ptr allocator: collections.AllocatorManager_AllocatorHandle, array: ^collections.NativeArray(ArchetypeChunk)),
    GetASHForComponent: proc "cdecl" (state: ^SystemState, typeIndex: ^TypeIndex, isReadOnly: u8, ash: ^collections.AtomicSafetyHandle),
    stableTypeHashToTypeIndex: ^collections.UnsafeParallelHashMap(u64, TypeIndex)
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

// GetStableHashFromType :: proc ($T: typeid)
// {
//     hash := HashTypeName(type);
//     when !collections.UNITY_DOTSRUNTIME {
//                 // UnityEngine objects have their own serialization mechanism so exclude hashing the type's
//                 // internals and just hash its name+assemblyname (not fully qualified)
//                 if (TypeManager.UnityEngineObjectType?.IsAssignableFrom(type) == true)
//                 {
//                     return CombineFNV1A64(hash, FNV1A64(type.Assembly.GetName().Name));
//                 }

//                 type_info_of(T).variant.(runtime.Type_Info_Named)
//     }
//                 if (type.IsGenericParameter || type.IsArray || type.IsPointer || type.IsPrimitive || type.IsEnum || WorkaroundTypes.Contains(type))
//                     return hash;
    
//                 foreach (var field in type.GetFields(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public))
//                 {
//                     if (!field.IsStatic) // statics have no effect on data layout
//                     {
//                         var fieldType = field.FieldType;
    
//                         if (!cache.TryGetValue(fieldType, out ulong fieldTypeHash))
//                         {
//                             // Classes can have cyclical type definitions so to prevent a potential stackoverflow
//                             // we make all future occurence of fieldType resolve to the hash of its field type name
//                             cache.Add(fieldType, HashTypeName(fieldType));
//                             fieldTypeHash = HashType(fieldType, cache);
//                             cache[fieldType] = fieldTypeHash;
//                         }
    
//                         var fieldOffsetAttrs = field.GetCustomAttributes(typeof(FieldOffsetAttribute));
//                         if (fieldOffsetAttrs.Any())
//                         {
//                             var offset = ((FieldOffsetAttribute)fieldOffsetAttrs.First()).Value;
//                             hash = CombineFNV1A64(hash, (ulong)offset);
//                         }
    
//                         hash = CombineFNV1A64(hash, fieldTypeHash);
//                     }
//                 }
    
//                 return hash;
// }

//         // http://www.isthe.com/chongo/src/fnv/hash_64a.c
//         // with basis and prime:
//         const ulong kFNV1A64OffsetBasis = 14695981039346656037;
//         const ulong kFNV1A64Prime = 1099511628211;

//         /// <summary>
//         /// Generates a FNV1A64 hash.
//         /// </summary>
//         /// <param name="text">Text to hash.</param>
//         /// <returns>Hash of input string.</returns>
//         public static ulong FNV1A64(string text)
//         {
//             ulong result = kFNV1A64OffsetBasis;
//             foreach (var c in text)
//             {
//                 result = kFNV1A64Prime * (result ^ (byte)(c & 255));
//                 result = kFNV1A64Prime * (result ^ (byte)(c >> 8));
//             }
//             return result;
//         }

//         /// <summary>
//         /// Generates a FNV1A64 hash.
//         /// </summary>
//         /// <param name="text">Text to hash.</param>
//         /// <typeparam name="T">Unmanaged IUTF8 type.</typeparam>
//         /// <returns>Hash of input string.</returns>
//         public static ulong FNV1A64<T>(T text)
//             where T : unmanaged, INativeList<byte>, IUTF8Bytes
//         {
//             ulong result = kFNV1A64OffsetBasis;
//             for(int i = 0; i <text.Length; ++i)
//             {
//                 var c = text[i];
//                 result = kFNV1A64Prime * (result ^ (byte)(c & 255));
//                 result = kFNV1A64Prime * (result ^ (byte)(c >> 8));
//             }
//             return result;
//         }

//         /// <summary>
//         /// Generates a FNV1A64 hash.
//         /// </summary>
//         /// <param name="val">Value to hash.</param>
//         /// <returns>Hash of input.</returns>
//         public static ulong FNV1A64(int val)
//         {
//             ulong result = kFNV1A64OffsetBasis;
//             unchecked
//             {
//                 result = (((ulong)(val & 0x000000FF) >>  0) ^ result) * kFNV1A64Prime;
//                 result = (((ulong)(val & 0x0000FF00) >>  8) ^ result) * kFNV1A64Prime;
//                 result = (((ulong)(val & 0x00FF0000) >> 16) ^ result) * kFNV1A64Prime;
//                 result = (((ulong)(val & 0xFF000000) >> 24) ^ result) * kFNV1A64Prime;
//             }

//             return result;
//         }

//         /// <summary>
//         /// Combines a FNV1A64 hash with a value.
//         /// </summary>
//         /// <param name="hash">Input Hash.</param>
//         /// <param name="value">Value to add to the hash.</param>
//         /// <returns>A combined FNV1A64 hash.</returns>
//         public static ulong CombineFNV1A64(ulong hash, ulong value)
//         {
//             hash ^= value;
//             hash *= kFNV1A64Prime;

//             return hash;
//         }

//         private static ulong HashNamespace(Type type)
//         {
//             var hash = kFNV1A64OffsetBasis;

//             // System.Reflection and Cecil don't report namespaces the same way so do an alternative:
//             // Find the namespace of an un-nested parent type, then hash each of the nested children names
//             if (type.IsNested)
//             {
//                 hash = CombineFNV1A64(hash, HashNamespace(type.DeclaringType));
//                 hash = CombineFNV1A64(hash, FNV1A64(type.DeclaringType.Name));
//             }
//             else if (!string.IsNullOrEmpty(type.Namespace))
//                 hash = CombineFNV1A64(hash, FNV1A64(type.Namespace));

//             return hash;
//         }

//         private static ulong HashTypeName(Type type)
//         {
//             ulong hash = HashNamespace(type);
//             hash = CombineFNV1A64(hash, FNV1A64(type.Name));
//             foreach (var ga in type.GenericTypeArguments)
//             {
//                 Assert.IsTrue(!ga.IsGenericParameter);
//                 hash = CombineFNV1A64(hash, HashTypeName(ga));
//             }

//             return hash;
//         }
