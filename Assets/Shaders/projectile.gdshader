shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords;

// Instance Custom Data:
// RGB = Velocity (Vector3)
// A = Spawn Time (float)
uniform float current_time;

void vertex() {
	vec3 velocity = INSTANCE_CUSTOM.rgb;
	float spawn_time = INSTANCE_CUSTOM.a;
	
	// Calculate time elapsed since spawn
	float age = current_time - spawn_time;
	
	// Apply displacement based on velocity and age
	// Since we use world_vertex_coords, VERTEX is already in world space (Initial Position + Rotation)
	// We just add the displacement vector.
	VERTEX += velocity * age;
}

void fragment() {
	ALBEDO = vec3(1.0, 1.0, 0.0);
	EMISSION = vec3(1.0, 0.5, 0.0) * 2.0;
}
