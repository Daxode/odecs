package odecs

import "core:log"
import "core:math"
import "core:runtime"

import "entities"
import "collections"

odecs_context: runtime.Context

@export
init :: proc "c" (funcs_that_call_unity: ^entities.functions_that_call_unity) {
    entities.unity_funcs = funcs_that_call_unity^
    odecs_context = entities.unity_funcs.odecs_context^
    context = odecs_context
    log.debug("Odecs has initialized succesfully")
}

LocalTransform :: struct
{
    Position : [3]f32,
    Scale : f32,
    Rotation : quaternion128
}

SpinSpeed :: struct {
    radiansPerSecond : f32
}

@export
Rotate :: proc "c" (state: ^entities.SystemState, query: ^entities.EntityQuery, transform_handle: ^entities.ComponentTypeHandle(LocalTransform), spinspeed_handle: ^entities.ComponentTypeHandle(SpinSpeed))
{
    context = odecs_context
    time := state.m_WorldUnmanaged.m_Impl.CurrentTime;
    entities.Update(transform_handle, state)
    entities.Update(spinspeed_handle, state)
    
    chunks := entities.ToArchetypeChunkArray(query, entities.GetWorldUpdateAllocator(state))
    for &chunk in chunks {
        transforms := entities.Chunk_GetComponentDataRW(&chunk, transform_handle)
        spinspeeds := entities.Chunk_GetComponentDataRO(&chunk, spinspeed_handle)
        for &transform, i in transforms
        {
            transform.Rotation *= RotateY(time.DeltaTime * spinspeeds[i].radiansPerSecond);
            transform.Position.y = math.sin(f32(time.ElapsedTime));
            log.debug(transform, spinspeeds[i], time)
        }
    }
} 

RotateY :: proc "contextless" (angle: f32) -> quaternion128
{
    sina, cosa := math.sincos(0.5 * angle);
    return quaternion(sina, 0.0, cosa, 0.0);
}