#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct AircraftData {
    mat4 transform;
    vec4 velocity_speed; // xyz = velocity, w = current_speed
    vec4 state;          // x = current_pitch, y = current_roll, z = throttle, w = unused
    vec4 inputs;         // x = input_pitch, y = input_roll, z = input_yaw, w = delta
    vec4 params_1;       // x = max_speed, y = min_speed, z = acceleration, w = drag_factor
    vec4 params_2;       // x = pitch_speed, y = roll_speed, z = pitch_accel, w = roll_accel
    vec4 factors;        // x = engine_factor, y = lift_factor, z = h_tail_factor, w = roll_authority
    vec4 factors_2;      // x = wing_imbalance, y = v_tail_factor, z = unused, w = unused
};

layout(set = 0, binding = 0, std430) buffer AircraftBuffer {
    AircraftData aircrafts[];
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

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= aircrafts.length()) {
        return;
    }

    AircraftData data = aircrafts[idx];
    
    float delta = data.inputs.w;
    if (delta <= 0.00001) return;

    // Unpack
    vec3 position = data.transform[3].xyz;
    mat3 basis = mat3(data.transform); // Extract rotation (upper-left 3x3)
    vec3 velocity = data.velocity_speed.xyz;
    float current_speed = data.velocity_speed.w;
    
    float current_pitch = data.state.x;
    float current_roll = data.state.y;
    float throttle = data.state.z;
    
    float input_pitch = data.inputs.x;
    float input_roll = data.inputs.y;
    
    float max_speed = data.params_1.x;
    float min_speed = data.params_1.y;
    float acceleration = data.params_1.z;
    float drag_factor = data.params_1.w;
    
    float pitch_speed = data.params_2.x;
    float roll_speed = data.params_2.y;
    float pitch_accel = data.params_2.z;
    float roll_accel = data.params_2.w;
    
    float engine_factor = data.factors.x;
    float lift_factor = data.factors.y;
    float h_tail_factor = data.factors.z;
    float roll_authority = data.factors.w;
    
    float wing_imbalance = data.factors_2.x;

    // --- Logic ---

    // 1. Speed Calculation
    vec3 forward = -basis[2]; // -Z is forward
    vec3 local_up = basis[1]; // Y is up
    
    float thrust = throttle * acceleration * engine_factor * 2.0;
    float drag = current_speed * current_speed * drag_factor;
    float gravity_influence = -9.8 * forward.y;
    
    current_speed += (thrust - drag + gravity_influence) * delta;
    current_speed = max(current_speed, min_speed);
    
    // 2. Rotation Logic
    // Pitch
    float target_pitch = input_pitch * pitch_speed * h_tail_factor;
    if (h_tail_factor < 0.9) {
        target_pitch -= (1.0 - h_tail_factor) * 1.5;
    }
    current_pitch = move_toward(current_pitch, target_pitch, pitch_accel * delta);
    
    // Roll
    float target_roll = input_roll * roll_speed * roll_authority;
    target_roll += wing_imbalance * 3.0;
    current_roll = move_toward(current_roll, target_roll, roll_accel * delta);
    
    // Apply Rotation
    float pitch_delta = current_pitch * delta;
    float roll_delta = current_roll * delta;
    
    // Rotation around X (Pitch)
    float c = cos(pitch_delta);
    float s = sin(pitch_delta);
    mat3 rot_x = mat3(
        1.0, 0.0, 0.0,
        0.0, c, s,
        0.0, -s, c
    );
    
    // Rotation around Z (Roll)
    c = cos(roll_delta);
    s = sin(roll_delta);
    mat3 rot_z = mat3(
        c, s, 0.0,
        -s, c, 0.0,
        0.0, 0.0, 1.0
    );
    
    // Apply rotations: Basis * Rot
    basis = basis * rot_x;
    basis = basis * rot_z;
    
    // Re-orthogonalize
    basis[0] = normalize(basis[0]);
    basis[1] = normalize(cross(basis[2], basis[0])); // Z x X = Y? No.
    // Right Hand Rule: X x Y = Z. Y x Z = X. Z x X = Y.
    // basis[0] is X (Right). basis[2] is Z (Back).
    // cross(Z, X) = Y. Correct.
    basis[2] = normalize(cross(basis[0], basis[1])); // X x Y = Z. Correct.
    
    // Update forward/up
    forward = -basis[2];
    local_up = basis[1];

    // 3. Velocity Calculation
    // Gravity
    velocity.y -= 9.8 * delta;
    
    // Lift
    float lift_intensity = (current_speed / max_speed) * 15.0 * lift_factor;
    velocity += local_up * lift_intensity * delta;
    
    // Thrust & Drag (Lerp)
    vec3 target_velocity = forward * current_speed;
    float inertia_factor = 2.0;
    velocity = lerp(velocity, target_velocity, inertia_factor * delta);
    
    // 4. Position Update
    position += velocity * delta;
    
    // Write back
    // Construct mat4 from basis and position
    data.transform = mat4(
        vec4(basis[0], 0.0),
        vec4(basis[1], 0.0),
        vec4(basis[2], 0.0),
        vec4(position, 1.0)
    );
    data.velocity_speed = vec4(velocity, current_speed);
    data.state.x = current_pitch;
    data.state.y = current_roll;
    
    aircrafts[idx] = data;
}
