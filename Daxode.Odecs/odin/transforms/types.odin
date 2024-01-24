package odecs_transforms

import math "../mathematics"

LocalTransform :: struct
{
    Position : math.float3,
    Scale : f32,
    Rotation : quaternion128
}