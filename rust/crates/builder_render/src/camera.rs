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
