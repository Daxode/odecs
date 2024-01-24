package odecs_collections

ToAllocator :: proc {ToAllocatorRewindableAllocator, ToAllocatorAllocatorManager_AllocatorHandle}

ToAllocatorRewindableAllocator :: proc "contextless" (allocatorHandle: RewindableAllocator) -> Allocator 
{
    return ToAllocator(allocatorHandle.m_handle)
}

ToAllocatorAllocatorManager_AllocatorHandle :: proc "contextless" (allocatorHandle: AllocatorManager_AllocatorHandle) -> Allocator 
{
    lo := allocatorHandle.Index;
    hi := allocatorHandle.Version;
    value := (u32(hi) << 16) | u32(lo);
    return Allocator(value);
}

import "core:log"


TryGetValue :: proc (mapp: ^UnsafeParallelHashMap($TKey, $TValue), key: TKey) -> (item: TValue, ok: b8)
{
    item_temp, _, ok_temp := TryGetFirstValueAtomic(TValue, mapp.m_Buffer, key)
    item = item_temp
    ok = ok_temp
    return
}

@(private)
TryGetFirstValueAtomic :: proc ($TValue: typeid, data: ^UnsafeParallelHashMapData, key: $TKey) -> (item: TValue, it: NativeParallelMultiHashMapIterator(TKey), ok: b8)
{
    it.key = key;
    

    if (data.allocatedIndexLength <= 0)
    {
        it.EntryIndex = -1;
        it.NextEntryIndex = -1;
        item = {};
        ok = false;
        return;
    }

    // First find the slot based on the hash
    bucket_index: i32
    when TKey == i32 {
        bucket_index = i32(key) & data.bucketCapacityMask;
    } else when TKey == u64 {
        key_hash := i32(key) ~ i32(u64(key) >> 32);
        bucket_index = key_hash & data.bucketCapacityMask;
    } else {
        #assert(false, "odecs hashmaps currently only support getting from i32 or u64 based keys!")
    }
    it.EntryIndex = data.buckets[bucket_index]
    it.NextEntryIndex = it.EntryIndex
    item, ok = TryGetNextValueAtomic(TValue, data, &it);
    return
}

@(private)
TryGetNextValueAtomic :: proc($TValue: typeid, data: ^UnsafeParallelHashMapData, it: ^NativeParallelMultiHashMapIterator($TKey)) -> (item: TValue, ok: b8)
{
    entryIdx := it.NextEntryIndex;
    it.NextEntryIndex = -1;
    it.EntryIndex = -1;
    item = {};
    if (entryIdx < 0 || entryIdx >= data.keyCapacity)
    {
        ok = false;
        return
    }

    keys_typed := ([^]TKey)(data.keys)
    values_typed := ([^]TValue)(data.values)

    nextPtrs := ([^]i32)(data.next);
    for (keys_typed[entryIdx] != it.key)
    {
        entryIdx = nextPtrs[entryIdx];
        if (entryIdx < 0 || entryIdx >= data.keyCapacity)
        {
            ok = false;
            return
        }
    }

    it.NextEntryIndex = nextPtrs[entryIdx];
    it.EntryIndex = entryIdx;

    // Read the value
    item = values_typed[entryIdx];
    ok = true;
    return
}