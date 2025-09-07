shader_type spatial;
render_mode unshaded, cull_disabled; // No lighting, always visible

// This will be set from TV.gd:
uniform sampler2D screen_texture;

void fragment() {
    // UV.y is flipped in Godot, so we invert it
    vec2 uv = vec2(UV.x, 1.0 - UV.y);

    vec3 tex_color = texture(screen_texture, uv).rgb;
    ALBEDO = tex_color;
    ALPHA = 1.0; // fully visible
}
