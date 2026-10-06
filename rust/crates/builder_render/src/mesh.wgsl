const MAX_JOINTS: u32 = 256u;

struct Camera {
    view_proj: mat4x4<f32>,
};

struct SkinPalette {
    matrices: array<mat4x4<f32>, 256>,
};

@group(0) @binding(0)
var<uniform> camera: Camera;

@group(0) @binding(1)
var<storage, read> skin: SkinPalette;

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

fn joint_matrix(index: u32) -> mat4x4<f32> {
    return skin.matrices[min(index, MAX_JOINTS - 1u)];
}

@vertex
fn vs_main(input: VertexIn) -> VertexOut {
    let weight_sum = input.weights.x + input.weights.y + input.weights.z + input.weights.w;
    var model = mat4x4<f32>(
        vec4<f32>(1.0, 0.0, 0.0, 0.0),
        vec4<f32>(0.0, 1.0, 0.0, 0.0),
        vec4<f32>(0.0, 0.0, 1.0, 0.0),
        vec4<f32>(0.0, 0.0, 0.0, 1.0),
    );

    if (weight_sum > 0.00001) {
        model =
            joint_matrix(input.joints.x) * input.weights.x +
            joint_matrix(input.joints.y) * input.weights.y +
            joint_matrix(input.joints.z) * input.weights.z +
            joint_matrix(input.joints.w) * input.weights.w;
    }

    let skinned_position = model * vec4<f32>(input.position, 1.0);
    let skinned_normal = normalize((model * vec4<f32>(input.normal, 0.0)).xyz);

    var out: VertexOut;
    out.clip_position = camera.view_proj * skinned_position;
    out.normal = skinned_normal;
    return out;
}

@fragment
fn fs_main(input: VertexOut) -> @location(0) vec4<f32> {
    let light = normalize(vec3<f32>(0.35, 0.8, 0.45));
    let diffuse = max(dot(normalize(input.normal), light), 0.18);
    return vec4<f32>(vec3<f32>(0.56, 0.34, 0.95) * diffuse, 1.0);
}
