struct Camera {
    view_proj: mat4x4<f32>,
};

struct JointPalette {
    matrices: array<mat4x4<f32>>,
};

@group(0) @binding(0)
var<uniform> camera: Camera;

@group(1) @binding(0)
var<storage, read> joint_palette: JointPalette;

struct VertexIn {
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) joints: vec4<u32>,
    @location(4) weights: vec4<f32>,
};

struct VertexOut {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) normal: vec3<f32>,
};

fn identity_matrix() -> mat4x4<f32> {
    return mat4x4<f32>(
        vec4<f32>(1.0, 0.0, 0.0, 0.0),
        vec4<f32>(0.0, 1.0, 0.0, 0.0),
        vec4<f32>(0.0, 0.0, 1.0, 0.0),
        vec4<f32>(0.0, 0.0, 0.0, 1.0),
    );
}

fn zero_matrix() -> mat4x4<f32> {
    return mat4x4<f32>(
        vec4<f32>(0.0),
        vec4<f32>(0.0),
        vec4<f32>(0.0),
        vec4<f32>(0.0),
    );
}

fn skin_matrix(input: VertexIn) -> mat4x4<f32> {
    let joint_count = arrayLength(&joint_palette.matrices);
    var skin = zero_matrix();
    var total_weight = 0.0;

    if input.weights.x > 0.0 && input.joints.x < joint_count {
        skin = skin + joint_palette.matrices[input.joints.x] * input.weights.x;
        total_weight = total_weight + input.weights.x;
    }
    if input.weights.y > 0.0 && input.joints.y < joint_count {
        skin = skin + joint_palette.matrices[input.joints.y] * input.weights.y;
        total_weight = total_weight + input.weights.y;
    }
    if input.weights.z > 0.0 && input.joints.z < joint_count {
        skin = skin + joint_palette.matrices[input.joints.z] * input.weights.z;
        total_weight = total_weight + input.weights.z;
    }
    if input.weights.w > 0.0 && input.joints.w < joint_count {
        skin = skin + joint_palette.matrices[input.joints.w] * input.weights.w;
        total_weight = total_weight + input.weights.w;
    }

    if total_weight <= 0.00000001 {
        return identity_matrix();
    }
    return skin * (1.0 / total_weight);
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    var out: VertexOut;
    let skin = skin_matrix(input);
    let skinned_position = skin * vec4<f32>(input.position, 1.0);
    let skinned_normal = (skin * vec4<f32>(input.normal, 0.0)).xyz;

    out.clip_position = camera.view_proj * skinned_position;
    if dot(skinned_normal, skinned_normal) > 0.00000001 {
        out.normal = normalize(skinned_normal);
    } else {
        out.normal = input.normal;
    }
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let light = normalize(vec3<f32>(0.35, 0.8, 0.45));
    let n = normalize(input.normal);
    let diffuse = max(dot(n, light), 0.18);
    return vec4<f32>(vec3<f32>(0.56, 0.34, 0.95) * diffuse, 1.0);
}
