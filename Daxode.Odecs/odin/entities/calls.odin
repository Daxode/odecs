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


GetStableHashFromType :: proc (T: typeid) -> u64
{
    // ulong versionHash = HashVersionAttribute(type, customAttributes);
    typeHash := HashType(T);
    return CombineFNV1A64(FNV1A64_i32(0), typeHash);
}

@private
HashType :: proc (T: typeid) -> u64
{
    hashed_val := HashTypeName(T);
    // when !collections.UNITY_DOTSRUNTIME {
                // UnityEngine objects have their own serialization mechanism so exclude hashing the type's
                // internals and just hash its name+assemblyname (not fully qualified)
                // if (TypeManager.UnityEngineObjectType?.IsAssignableFrom(type))
                // {
                //     return CombineFNV1A64(hash, FNV1A64(type.Assembly.GetName().Name));
                // }
    // }



    // if (type.IsGenericParameter || type.IsArray || type.IsPointer || type.IsPrimitive || type.IsEnum || WorkaroundTypes.Contains(type))
    //     return hash;

        
    #partial switch info in type_info_of(T).variant
    {
        case runtime.Type_Info_Named:
            structinfo, structinfo_ok := info.base.variant.(runtime.Type_Info_Struct);
            if (structinfo_ok) {
                for field_type in structinfo.types
                {
                    // if (!cache.TryGetValue(fieldType, out ulong fieldTypeHash))
                        // {
                            // Classes can have cyclical type definitions so to prevent a potential stackoverflow
                            // we make all future occurence of fieldType resolve to the hash of its field type name
                            // cache.Add(fieldType, HashTypeName(fieldType));
                            fieldTypeHash := HashType(field_type.id);
                            // cache[fieldType] = fieldTypeHash;
                        // }
    
                        // var fieldOffsetAttrs = field.GetCustomAttributes(typeof(FieldOffsetAttribute));
                        // if (fieldOffsetAttrs.Any())
                        // {
                        //     var offset = ((FieldOffsetAttribute)fieldOffsetAttrs.First()).Value;
                        //     hashed_val = CombineFNV1A64(hashed_val, (ulong)offset);
                        // }
    
                        hashed_val = CombineFNV1A64(hashed_val, fieldTypeHash);
                }
            } else {
                // log.info("doesn't need to recurse into" , info.pkg, info.name)
            }
    }

    // return hash;
    return hashed_val;
}

// http://www.isthe.com/chongo/src/fnv/hash_64a.c
// with basis and prime:
kFNV1A64OffsetBasis :u64: 14695981039346656037;
kFNV1A64Prime :u64: 1099511628211;

/// <summary>
/// Generates a FNV1A64 hash.
/// </summary>
/// <param name="text">Text to hash.</param>
/// <returns>Hash of input string.</returns>
FNV1A64_str :: proc (text: string) -> u64
{
    result := kFNV1A64OffsetBasis;
    for c in text
    {
        result = kFNV1A64Prime * (result ~ u64(c & 255));
        result = kFNV1A64Prime * (result ~ u64(c >> 8));
    }
    return result;
}

/// <summary>
/// Generates a FNV1A64 hash.
/// </summary>
/// <param name="val">Value to hash.</param>
/// <returns>Hash of input.</returns>
FNV1A64_i32 :: proc (val: i32) -> u64
{
    result: = kFNV1A64OffsetBasis;

    result = ((u64(u32(val) & 0x000000FF) >>  u64(0)) ~ result) * kFNV1A64Prime;
    result = ((u64(u32(val) & 0x0000FF00) >>  u64(8)) ~ result) * kFNV1A64Prime;
    result = ((u64(u32(val) & 0x00FF0000) >> u64(16)) ~ result) * kFNV1A64Prime;
    result = ((u64(u32(val) & 0xFF000000) >> u64(24)) ~ result) * kFNV1A64Prime;

    return result;
}

/// <summary>
/// Combines a FNV1A64 hash with a value.
/// </summary>
/// <param name="hash">Input Hash.</param>
/// <param name="value">Value to add to the hash.</param>
/// <returns>A combined FNV1A64 hash.</returns>
CombineFNV1A64 :: proc (hash_val, value: u64) -> u64
{
    hashed_val := hash_val ~ value;
    hashed_val *= kFNV1A64Prime;

    return hashed_val;
}

NameSpaces := map[string]u64{
	"odecs_entities" = FNV1A64_str("Unity.Entities"),
	"odecs_transforms" = FNV1A64_str("Unity.Transforms"),
    "odecs_mathematics" = FNV1A64_str("Unity.Mathematics"),
}

HashNamespace :: proc(type: typeid) -> u64
{
    hashed_val := kFNV1A64OffsetBasis;
    #partial switch info in type_info_of(type).variant {
        case runtime.Type_Info_Named:
            namespace_hash, found_hash := NameSpaces[info.pkg]
            if found_hash {
                // log.debug(info.pkg, namespace_hash)
                return CombineFNV1A64(hashed_val, namespace_hash)
            }

        case runtime.Type_Info_Array:
            // log.debug(info.elem.variant)
            return 0
        case runtime.Type_Info_Float:
            return 0
        case runtime.Type_Info_Quaternion:
            return 0
    }

    // System.Reflection and Cecil don't report namespaces the same way so do an alternative:
    // Find the namespace of an un-nested parent type, then hash each of the nested children names
    // if (type.IsNested)
    // {
    //     hashed_val = CombineFNV1A64(hashed_val, HashNamespace(type.DeclaringType));
    //     hashed_val = CombineFNV1A64(hashed_val, FNV1A64(type.DeclaringType.Name));
    // }
    // else if (!string.IsNullOrEmpty(type.Namespace))
    //     hashed_val = CombineFNV1A64(hashed_val, FNV1A64_str(type.Namespace));

    

    return hashed_val;
}


GetTypeIndex :: proc($type: typeid) -> TypeIndex
{
    val, _ := collections.TryGetValue(unity_funcs.stableTypeHashToTypeIndex, u64(GetStableHashFromType(type)))
    return val
}

import "core:hash"
import "core:strings"
import "core:mem"
HashTypeName::proc(type: typeid) -> u64
{
    
    hashed_val := HashNamespace(type);

    // log.debug(type_info_of(type).variant)

    #partial switch info in type_info_of(type).variant
    {
        case runtime.Type_Info_Named:
            base_arr, has_arr_base := info.base.variant.(runtime.Type_Info_Array)
            if has_arr_base && base_arr.elem.id == f32 {
                float_hash := CombineFNV1A64(CombineFNV1A64(kFNV1A64OffsetBasis, FNV1A64_str("System")) , FNV1A64_str("Single"))
                
                switch base_arr.count {
                    case 2:
                        hashed_val = FNV1A64_str("float2")
                    case 3:
                        hashed_val = FNV1A64_str("float3")
                    case 4:
                        hashed_val = FNV1A64_str("float4")
                }
                
                hashed_val := CombineFNV1A64(CombineFNV1A64(kFNV1A64OffsetBasis, FNV1A64_str("Unity.Mathematics")), hashed_val)
                for i in 0..<base_arr.count {
                    hashed_val = CombineFNV1A64(hashed_val, float_hash);
                }
                return hashed_val
            } else {
                hashed_val = CombineFNV1A64(hashed_val, FNV1A64_str(info.name))
                return hashed_val
            }

        case runtime.Type_Info_Float:
            hashed_system_namespace := CombineFNV1A64(kFNV1A64OffsetBasis, FNV1A64_str("System"))            
            hashed_val = CombineFNV1A64(hashed_system_namespace, FNV1A64_str("Single"))
            // log.debug("Float: ", hashed_val)
            return hashed_val
        case runtime.Type_Info_Quaternion:
            hashed_namespace := CombineFNV1A64(kFNV1A64OffsetBasis, FNV1A64_str("Unity.Mathematics"))
            outer_type := CombineFNV1A64(hashed_namespace, FNV1A64_str("quaternion"))
            float4_hash := CombineFNV1A64(hashed_namespace, FNV1A64_str("float4"))

            float_hash := CombineFNV1A64(CombineFNV1A64(kFNV1A64OffsetBasis, FNV1A64_str("System")) , FNV1A64_str("Single"))
            for i in 0..<4 {
                float4_hash = CombineFNV1A64(float4_hash, float_hash);
            }
            // log.debug("Float4: ", float4_hash)
            
            outer_type = CombineFNV1A64(outer_type, float4_hash);

            // log.debug("quaternion: ", outer_type)
            return outer_type
        case runtime.Type_Info_Array:

    }


    
    // foreach (var ga in type.GenericTypeArguments)
    // {
    //     Assert.IsTrue(!ga.IsGenericParameter);
    //     hash = CombineFNV1A64(hash, HashTypeName(ga));
    // }

    return hashed_val;
}
