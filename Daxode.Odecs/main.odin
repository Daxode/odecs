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

functions_that_call_unity :: struct {
    debugLog: proc "cdecl" (str: cstring, len: int)
}

@export
init :: proc "c" (funcs_that_call_unity: ^functions_that_call_unity) {
    odecs_context = runtime.default_context()
    odecs_context.logger = {
        options = {.Short_File_Path, .Line},
        data = rawptr(funcs_that_call_unity),
        procedure = proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
            funcs_that_call_unity := transmute(^functions_that_call_unity)(data)
            my_test := strings.clone_to_cstring(text)
            funcs_that_call_unity.debugLog(my_test, len(my_test)+1)
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

@export
Rotate :: proc "c" (entity_count_in_chunk: int, transforms: [^]LocalTransform, spinspeeds: [^]SpinSpeed, time: ^TimeData)
{
    context = odecs_context
    for &transform, i in transforms[:entity_count_in_chunk]
    {   
        transform.Rotation *= RotateY(time.DeltaTime * spinspeeds[i].radiansPerSecond);
        transform.Position.y = math.sin(f32(time.ElapsedTime));
    }
    vall: i32 = -5
    for val in test(&vall) {
        log.debug(val, vall)
    }

    // valy := LocalTransform{}
    // test_2(MyThing)
}

test :: proc(itr: ^i32) -> (val: i32, cond: b8) {
    if (itr^ < 3) {
        itr^ += 1
        val = itr^ * i32(2)
        cond = true
    } else {
        val = 5
        cond = false
    }

    return
}

ecs_component_group :: union {
    LocalTransform,
    SpinSpeed
}

test_2  :: proc($T: typeid) where intrinsics.type_is_struct(T) 
{
    mee, ok := type_info_of(T).variant.(runtime.Type_Info_Named)
    if ok {
        log.debug(mee.base.variant)
        #partial switch val in mee.base.variant {
            case runtime.Type_Info_Struct:
                log.debug(val)
        } 
    }
}

@(component)
MyThing :: struct {
    using testing: LocalTransform
}

RotateY :: proc "contextless" (angle: f32) -> quaternion128
{
    sina, cosa := math.sincos(0.5 * angle);
    return quaternion(sina, 0.0, cosa, 0.0);
}
