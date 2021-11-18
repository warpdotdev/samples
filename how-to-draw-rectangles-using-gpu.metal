#include <metal_stdlib>

using namespace metal;

#include "shader_types.h"

// Vertex shader outputs and fragment shader inputs
struct RectFragmentData
{
    float4 position [[position]];
    float2 pixel_position [[pixel_position]];
    float2 rect_origin;
    float2 rect_size;
    float2 rect_center;
    float2 rect_corner;
    float border_top;
    float border_right;
    float border_bottom;
    float border_left;
    float corner_radius_top;
    float corner_radius_bottom;
    float2 background_start;
    float2 background_end;
    float4 background_start_color;
    float4 background_end_color;
    float2 border_start;
    float2 border_end;
    float4 border_start_color;
    float4 border_end_color;
};

float distance_from_rect(vector_float2 pixel_pos, vector_float2 rect_center, vector_float2 rect_corner, float corner_radius) {
    vector_float2 p = pixel_pos - rect_center;
    vector_float2 q = abs(p) - rect_corner + corner_radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;
}

float4 derive_color(float2 pixel_pos, float2 start, float2 end, float4 start_color, float4 end_color) {
    float2 adjusted_end = end - start;
    float h = dot(pixel_pos - start, adjusted_end) / dot(adjusted_end, adjusted_end);
    return mix(start_color, end_color, h);
}

vertex RectFragmentData
rect_vertex_shader(
    uint vertex_id [[vertex_id]],
    ushort instance_id [[instance_id]],
    constant float2 *vertices [[buffer(0)]],
    constant PerRectUniforms *glyph_uniforms [[buffer(1)]],
    constant Uniforms *uniforms [[buffer(2)]])
{
    const constant PerRectUniforms *rect = &glyph_uniforms[instance_id];

    float2 pixel_pos = vertices[vertex_id] * rect->size + rect->origin;
    float2 device_pos = pixel_pos / uniforms->viewport_size * float2(2.0, -2.0) + float2(-1.0, 1.0);

    RectFragmentData out;
    out.position = float4(device_pos, 0.0, 1.0);
    out.pixel_position = pixel_pos;
    out.rect_origin = rect->origin;
    out.rect_size = rect->size;
    out.rect_corner = rect->size / 2.0;
    out.rect_center = rect->origin + out.rect_corner;
    out.border_top = rect->border_top;
    out.border_right = rect->border_right;
    out.border_bottom = rect->border_bottom;
    out.border_left = rect->border_left;
    out.corner_radius_top = rect->corner_radius_top;
    out.corner_radius_bottom = rect->corner_radius_bottom;
    out.background_start = rect->background_start * rect->size + rect->origin;
    out.background_end = rect->background_end * rect->size + rect->origin;
    out.background_start_color = rect->background_start_color;
    out.background_end_color = rect->background_end_color;
    out.border_start = rect->border_start * rect->size + rect->origin;
    out.border_end = rect->border_end * rect->size + rect->origin;
    out.border_start_color = rect->border_start_color;
    out.border_end_color = rect->border_end_color;
    return out;
}

fragment float4 rect_fragment_shader(
    RectFragmentData in [[stage_in]],
    constant Uniforms *uniforms [[buffer(0)]])
{
    float shape_distance;
    float background_distance;
    float corner_radius;

  
    float2 border_corner = in.rect_corner;
    if (in.position.y >= in.rect_center.y) {
        border_corner.y -= in.border_bottom;
        corner_radius = in.corner_radius_bottom;
    } else {
        border_corner.y -= in.border_top;
        corner_radius = in.corner_radius_top;
    }
    if (in.position.x >= in.rect_center.x) {
        border_corner.x -= in.border_right;
    } else {
        border_corner.x -= in.border_left;
    }
    shape_distance = distance_from_rect(in.position.xy, in.rect_center, in.rect_corner, corner_radius);
    background_distance = distance_from_rect(in.position.xy, in.rect_center, border_corner, corner_radius);
    
    float4 color;
    float4 background_color = derive_color(in.position.xy, in.background_start, in.background_end, in.background_start_color, in.background_end_color);
    float4 border_color = derive_color(in.position.xy, in.border_start, in.border_end, in.border_start_color, in.border_end_color);
    color = background_color;

    // Only blend in the color with the border color if we're actually rendering a border color.
    if (border_color.a != 0) {
        color = mix(background_color, border_color, smoothstep(-0.5, 0.5, background_distance));
    }

    // If there's a corner radius we need to do some anti aliasing to smooth out the rounded corner effect.
    if (corner_radius > 0) {
        color.a *= 1.0 - smoothstep(-0.75, -0.1, shape_distance);
    }
    return color;
}