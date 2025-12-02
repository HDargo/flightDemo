#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct MissileData {
    mat4 transform;
    vec4 velocity_speed; // xyz = velocity, w = current_speed
    vec4 target_pos_life; // xyz = target_position, w = current_life
    vec4 params;         // x = max_speed, y = acceleration, z = turn_speed, w = max_lifetime
    vec4 state_flags;    // x = state (0: Active, 1: Explode, 2: Dead), y = has_target (0/1), z, w unused
};

layout(set = 0, binding = 0, std430) buffer MissileBuffer {
    MissileData missiles[];
};

// Helper for move_toward
float move_toward(float current, float target, float max_delta) {
    if (abs(target - current) <= max_delta) {
        return target;
    }
    return current + sign(target - current) * max_delta;
}

// Helper for lerp
vec3 lerp(vec3 a, vec3 b, float t) {
    return a + (b - a) * t;
}

// Helper for slerp (Quaternion-free approximation or matrix based)
// Since we use basis vectors, we can rotate towards target vector.
mat3 rotate_towards(mat3 current_basis, vec3 target_dir, float max_angle) {
    vec3 current_dir = -current_basis[2]; // Forward is -Z
    
    // Avoid precision issues
    if (length(target_dir) < 0.001 || length(current_dir) < 0.001) return current_basis;
    
    target_dir = normalize(target_dir);
    current_dir = normalize(current_dir);
    
    float dot_prod = dot(current_dir, target_dir);
    dot_prod = clamp(dot_prod, -1.0, 1.0);
    
    float angle = acos(dot_prod);
    
    if (angle <= max_angle) {
        // Can reach target in this step
        // Construct new basis looking at target_dir
        // We need an up vector. Try to preserve current up, or use world up.
        vec3 up = current_basis[1];
        vec3 right = cross(target_dir, up);
        
        if (length(right) < 0.001) {
            // Target is parallel to up, choose another up
            up = vec3(1.0, 0.0, 0.0);
            right = cross(target_dir, up);
        }
        
        right = normalize(right);
        up = normalize(cross(right, target_dir));
        
        return mat3(right, up, -target_dir);
    }
    
    // Rotate by max_angle
    vec3 axis = cross(current_dir, target_dir);
    if (length(axis) < 0.001) {
        // Parallel or anti-parallel
        // If anti-parallel (dot < 0), pick any axis
        if (dot_prod < 0.0) axis = vec3(0.0, 1.0, 0.0);
        else return current_basis; // Already aligned
    }
    axis = normalize(axis);
    
    float c = cos(max_angle);
    float s = sin(max_angle);
    float t = 1.0 - c;
    
    // Rotation matrix from axis-angle
    mat3 rot = mat3(
        t*axis.x*axis.x + c,        t*axis.x*axis.y + axis.z*s, t*axis.x*axis.z - axis.y*s,
        t*axis.x*axis.y - axis.z*s, t*axis.y*axis.y + c,        t*axis.y*axis.z + axis.x*s,
        t*axis.x*axis.z + axis.y*s, t*axis.y*axis.z - axis.x*s, t*axis.z*axis.z + c
    );
    
    return rot * current_basis;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= missiles.length()) {
        return;
    }

    MissileData data = missiles[idx];
    
    // Check state
    if (data.state_flags.x > 0.5) return; // Already dead or exploding
    
    // Delta time passed in params or uniform? 
    // Let's assume we pack delta into state_flags.z for now or use a uniform.
    // For simplicity, let's use state_flags.z as delta since it was unused.
    float delta = data.state_flags.z;
    
    // 1. Lifetime
    data.target_pos_life.w += delta;
    if (data.target_pos_life.w >= data.params.w) {
        data.state_flags.x = 1.0; // Explode
        missiles[idx] = data;
        return;
    }
    
    // Unpack
    mat3 basis = mat3(data.transform);
    vec3 position = data.transform[3].xyz;
    vec3 velocity = data.velocity_speed.xyz;
    float current_speed = data.velocity_speed.w;
    
    vec3 target_pos = data.target_pos_life.xyz;
    float max_speed = data.params.x;
    float acceleration = data.params.y;
    float turn_speed = data.params.z;
    bool has_target = data.state_flags.y > 0.5;
    
    // 2. Accelerate
    current_speed = move_toward(current_speed, max_speed, acceleration * delta);
    
    // 3. Homing
    if (has_target) {
        vec3 to_target = target_pos - position;
        basis = rotate_towards(basis, to_target, turn_speed * delta);
    }
    
    // 4. Move
    vec3 forward = -basis[2];
    vec3 target_velocity = forward * current_speed;
    
    // Inertia
    velocity = lerp(velocity, target_velocity, 5.0 * delta);
    position += velocity * delta;
    
    // Write back
    data.transform = mat4(
        vec4(basis[0], 0.0),
        vec4(basis[1], 0.0),
        vec4(basis[2], 0.0),
        vec4(position, 1.0)
    );
    data.velocity_speed = vec4(velocity, current_speed);
    
    missiles[idx] = data;
}
