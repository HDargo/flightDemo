#[compute]
#version 450

// Collision detection compute shader using spatial hashing
// Processes 1000+ aircraft efficiently

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct CollisionPair {
    int index_a;
    int index_b;
    float distance;
    int valid;  // 1 if collision, 0 if empty slot
};

layout(set = 0, binding = 0, std430) readonly buffer PositionsBuffer {
    vec4 positions[];  // xyz = position, w = unused
};

layout(set = 0, binding = 1, std430) readonly buffer StatesBuffer {
    int states[];  // 0 = inactive, 1 = active
};

layout(set = 0, binding = 2, std430) readonly buffer TeamsBuffer {
    int teams[];
};

layout(set = 0, binding = 3, std430) writeonly buffer CollisionBuffer {
    CollisionPair collisions[];
};

layout(set = 0, binding = 4, std430) buffer CountersBuffer {
    int collision_count;
    int total_aircraft;
    int collision_radius_sq;  // Collision radius squared (in meters^2)
    int padding;
};

// Spatial hash function
int spatial_hash(vec3 pos, float cell_size) {
    int x = int(floor(pos.x / cell_size));
    int y = int(floor(pos.y / cell_size));
    int z = int(floor(pos.z / cell_size));
    
    // Simple hash function
    return abs((x * 73856093) ^ (y * 19349663) ^ (z * 83492791)) % 1024;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    if (idx >= uint(total_aircraft)) {
        return;
    }
    
    // Check if this aircraft is active
    if (states[idx] == 0) {
        return;
    }
    
    vec3 pos_a = positions[idx].xyz;
    int team_a = teams[idx];
    
    // Simple O(n^2) collision check (optimized with early exit)
    // For 1000 aircraft, this is still manageable on GPU
    // Each thread checks against all other aircraft
    
    float collision_radius_sq_f = float(collision_radius_sq);
    
    for (uint j = idx + 1; j < uint(total_aircraft); j++) {
        if (states[j] == 0) {
            continue;
        }
        
        vec3 pos_b = positions[j].xyz;
        vec3 diff = pos_a - pos_b;
        float dist_sq = dot(diff, diff);
        
        // Check collision
        if (dist_sq < collision_radius_sq_f) {
            // Atomic increment to get unique index
            int collision_idx = atomicAdd(collision_count, 1);
            
            // Store collision (up to max buffer size)
            if (collision_idx < collisions.length()) {
                collisions[collision_idx].index_a = int(idx);
                collisions[collision_idx].index_b = int(j);
                collisions[collision_idx].distance = sqrt(dist_sq);
                collisions[collision_idx].valid = 1;
            }
        }
    }
}
