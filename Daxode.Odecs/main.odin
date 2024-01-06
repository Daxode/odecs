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

odecs_context: runtime.Context

@export
init :: proc "c" (hello: proc "cdecl" (str: cstring, len: int)) {
    odecs_context = runtime.default_context()
    odecs_context.logger = {
        options = {.Short_File_Path, .Line},
        data = transmute(rawptr)(hello),
        procedure = proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
            hello := transmute(proc "cdecl" (str: cstring, len: int))(data)
            // builder := strings.builder_make()
            // strings.write_string(&builder, text)
            // strings.write_byte(&builder, '\n')
            // log.do_location_header(options, &builder, location)
            // strings.to_string(builder)
            my_test := strings.clone_to_cstring(text)
            hello(my_test, len(my_test)+1)
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
    log.debug("Yyayyy")
    log.debug("hello world")
}

RotateY :: proc "contextless" (angle: f32) -> quaternion128
{
    sina, cosa := math.sincos(0.5 * angle);
    return quaternion(sina, 0.0, cosa, 0.0);
}
