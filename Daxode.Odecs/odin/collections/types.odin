package odecs_collections

ENABLE_UNITY_COLLECTIONS_CHECKS :: #config(ENABLE_UNITY_COLLECTIONS_CHECKS, true)
UNITY_DOTS_DEBUG :: #config(UNITY_DOTS_DEBUG, false)

NativeArray :: struct($T: typeid) #packed where ENABLE_UNITY_COLLECTIONS_CHECKS {
    m_Buffer : [^]T,
    m_Length : i32,
    m_MinIndex, m_MaxIndex: i32,
    m_Safety: AtomicSafetyHandle,
    m_AllocatorLabel: Allocator
}

FixedString128Bytes :: struct #packed
{
    utf8LengthInBytes: u16,
    bytes: FixedBytes126
}
FixedBytes126 :: [126]u8
FixedBytes16 :: [16]u8

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


NativeParallelMultiHashMapIterator :: struct($TKey: typeid) {
    key: TKey,
    NextEntryIndex: i32,
    EntryIndex: i32,
}

UnsafeParallelHashMapData :: struct #align(8)
{
    values: [^]u8, // Byte*
    keys: [^]u8, // Byte*
    next: [^]u8, // Byte*
    buckets: [^]i32, // Byte*
    keyCapacity: i32, // Int32
    bucketCapacityMask: i32, // Int32
    allocatedIndexLength: i32, // Int32
    _: [1]u32, // padding
    _: [2]u64, // padding
    firstFreeTLS: [1024]u64, // <firstFreeTLS>e__FixedBuffer
} // total: 8256

UnsafeParallelHashMap :: struct($TKey, $TValue: typeid)
{
    m_Buffer: ^UnsafeParallelHashMapData, // UnsafeParallelHashMapData*
    m_AllocatorLabel: AllocatorManager_AllocatorHandle
}

NativeParallelHashMap :: struct($TKey, $TValue: typeid)
{
    m_HashMapData: UnsafeParallelHashMap(TKey, TValue),
    m_Safety: AtomicSafetyHandle
}

DoubleRewindableAllocators :: struct #packed
{
    Pointer: ^RewindableAllocator,
    UpdateAllocatorHelper: [2]AllocatorHelper(RewindableAllocator)
}

Union :: distinct i64
MemoryBlock :: struct #packed
{
    m_pointer: [^]u8,
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