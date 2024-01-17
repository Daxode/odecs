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