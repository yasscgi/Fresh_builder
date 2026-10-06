use std::f32::consts::{FRAC_PI_2, PI};

const MIN_PITCH: f32 = -FRAC_PI_2 + 0.02;
const MAX_PITCH: f32 = FRAC_PI_2 - 0.02;
const MIN_DISTANCE: f32 = 0.05;
const MAX_DISTANCE: f32 = 500.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ViewPreset {
    Front,
    Back,
    Left,
    Right,
    Top,
    Bottom,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ViewportCamera {
    pub yaw: f32,
    pub pitch: f32,
    pub distance: f32,
    pub target: [f32; 3],
}

impl Default for ViewportCamera {
    fn default() -> Self {
        Self {
            yaw: 0.0,
            pitch: 0.15,
            distance: 3.2,
            target: [0.0, 0.9, 0.0],
        }
    }
}

impl ViewportCamera {
    pub fn orbit(&mut self, delta_x: f32, delta_y: f32, sensitivity: f32) {
        let safe_sensitivity = sensitivity.clamp(0.0001, 0.1);
        self.yaw = wrap_angle(self.yaw - delta_x * safe_sensitivity);
        self.pitch = (self.pitch - delta_y * safe_sensitivity).clamp(MIN_PITCH, MAX_PITCH);
    }

    pub fn zoom(&mut self, delta: f32, sensitivity: f32) {
        let safe_sensitivity = sensitivity.clamp(0.0001, 0.2);
        let scale = (delta * safe_sensitivity).exp();
        self.distance = (self.distance * scale).clamp(MIN_DISTANCE, MAX_DISTANCE);
    }

    pub fn view_projection(&self, aspect: f32) -> [[f32; 4]; 4] {
        let safe_aspect = if aspect.is_finite() && aspect > 0.0001 {
            aspect
        } else {
            1.0
        };

        let cos_pitch = self.pitch.cos();
        let eye = [
            self.target[0] + self.distance * cos_pitch * self.yaw.sin(),
            self.target[1] + self.distance * self.pitch.sin(),
            self.target[2] + self.distance * cos_pitch * self.yaw.cos(),
        ];

        let view = look_at_rh(eye, self.target, [0.0, 1.0, 0.0]);
        let projection = perspective_rh_zo(45.0_f32.to_radians(), safe_aspect, 0.01, 1000.0);
        multiply_mat4(projection, view)
    }

    pub fn set_preset(&mut self, preset: ViewPreset) {
        match preset {
            ViewPreset::Front => {
                self.yaw = 0.0;
                self.pitch = 0.0;
            }
            ViewPreset::Back => {
                self.yaw = PI;
                self.pitch = 0.0;
            }
            ViewPreset::Left => {
                self.yaw = -FRAC_PI_2;
                self.pitch = 0.0;
            }
            ViewPreset::Right => {
                self.yaw = FRAC_PI_2;
                self.pitch = 0.0;
            }
            ViewPreset::Top => {
                self.yaw = 0.0;
                self.pitch = MAX_PITCH;
            }
            ViewPreset::Bottom => {
                self.yaw = 0.0;
                self.pitch = MIN_PITCH;
            }
        }
    }
}

fn wrap_angle(angle: f32) -> f32 {
    (angle + PI).rem_euclid(PI * 2.0) - PI
}

fn multiply_mat4(a: [[f32; 4]; 4], b: [[f32; 4]; 4]) -> [[f32; 4]; 4] {
    let mut out = [[0.0; 4]; 4];
    for column in 0..4 {
        for row in 0..4 {
            out[column][row] =
                a[0][row] * b[column][0] +
                a[1][row] * b[column][1] +
                a[2][row] * b[column][2] +
                a[3][row] * b[column][3];
        }
    }
    out
}

fn normalize(v: [f32; 3]) -> [f32; 3] {
    let len = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    if !len.is_finite() || len <= f32::EPSILON {
        return [0.0, 0.0, 0.0];
    }
    [v[0] / len, v[1] / len, v[2] / len]
}

fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn look_at_rh(eye: [f32; 3], target: [f32; 3], up: [f32; 3]) -> [[f32; 4]; 4] {
    let f = normalize([
        target[0] - eye[0],
        target[1] - eye[1],
        target[2] - eye[2],
    ]);
    let s = normalize(cross(f, up));
    let u = cross(s, f);

    [
        [s[0], u[0], -f[0], 0.0],
        [s[1], u[1], -f[1], 0.0],
        [s[2], u[2], -f[2], 0.0],
        [-dot(s, eye), -dot(u, eye), dot(f, eye), 1.0],
    ]
}

fn perspective_rh_zo(fovy: f32, aspect: f32, near: f32, far: f32) -> [[f32; 4]; 4] {
    let f = 1.0 / (fovy * 0.5).tan();
    [
        [f / aspect, 0.0, 0.0, 0.0],
        [0.0, f, 0.0, 0.0],
        [0.0, 0.0, far / (near - far), -1.0],
        [0.0, 0.0, (near * far) / (near - far), 0.0],
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn orbit_clamps_pitch_and_wraps_yaw() {
        let mut camera = ViewportCamera::default();
        camera.orbit(100_000.0, -100_000.0, 0.01);

        assert!(camera.yaw >= -PI && camera.yaw <= PI);
        assert!(camera.pitch <= MAX_PITCH);
    }

    #[test]
    fn zoom_cannot_cross_camera_limits() {
        let mut camera = ViewportCamera::default();

        camera.zoom(-100_000.0, 0.02);
        assert_eq!(camera.distance, MIN_DISTANCE);

        camera.zoom(100_000.0, 0.02);
        assert_eq!(camera.distance, MAX_DISTANCE);
    }

    #[test]
    fn presets_use_blender_style_cardinal_views() {
        let mut camera = ViewportCamera::default();
        camera.set_preset(ViewPreset::Right);

        assert!((camera.yaw - FRAC_PI_2).abs() < 1.0e-6);
        assert_eq!(camera.pitch, 0.0);
    }
}
