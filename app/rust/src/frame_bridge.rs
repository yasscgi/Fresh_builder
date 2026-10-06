use std::{
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Mutex, OnceLock,
    },
};

static CAPTURE_ENABLED: AtomicBool = AtomicBool::new(false);
static GENERATION: AtomicU64 = AtomicU64::new(0);
static FRAME: OnceLock<Mutex<PublishedFrame>> = OnceLock::new();

#[derive(Default)]
struct PublishedFrame {
    width: u32,
    height: u32,
    generation: u64,
    rgba: Vec<u8>,
}

fn frame() -> &'static Mutex<PublishedFrame> {
    FRAME.get_or_init(|| Mutex::new(PublishedFrame::default()))
}

pub fn capture_enabled() -> bool {
    CAPTURE_ENABLED.load(Ordering::Acquire)
}

pub fn publish(width: u32, height: u32, rgba: Vec<u8>) {
    if !capture_enabled() {
        return;
    }

    if rgba.len() != width as usize * height as usize * 4 {
        return;
    }

    let generation = GENERATION.fetch_add(1, Ordering::AcqRel) + 1;
    if let Ok(mut target) = frame().lock() {
        target.width = width;
        target.height = height;
        target.generation = generation;
        target.rgba = rgba;
    }
}

#[no_mangle]
pub extern "C" fn fresh_builder_frame_capture_enabled(enabled: bool) {
    CAPTURE_ENABLED.store(enabled, Ordering::Release);
    if !enabled {
        if let Ok(mut target) = frame().lock() {
            target.width = 0;
            target.height = 0;
            target.rgba.clear();
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn fresh_builder_copy_latest_frame(
    destination: *mut u8,
    capacity: usize,
    out_width: *mut u32,
    out_height: *mut u32,
    out_generation: *mut u64,
) -> usize {
    let Ok(target) = frame().lock() else {
        return 0;
    };

    if !out_width.is_null() {
        unsafe { *out_width = target.width };
    }
    if !out_height.is_null() {
        unsafe { *out_height = target.height };
    }
    if !out_generation.is_null() {
        unsafe { *out_generation = target.generation };
    }

    let required = target.rgba.len();
    if destination.is_null() || capacity < required || required == 0 {
        return required;
    }

    unsafe {
        ptr::copy_nonoverlapping(target.rgba.as_ptr(), destination, required);
    }
    required
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn publishes_and_copies_frame_when_capture_is_enabled() {
        fresh_builder_frame_capture_enabled(true);
        publish(2, 1, vec![1, 2, 3, 4, 5, 6, 7, 8]);

        let mut width = 0;
        let mut height = 0;
        let mut generation = 0;
        let required = unsafe {
            fresh_builder_copy_latest_frame(
                std::ptr::null_mut(),
                0,
                &mut width,
                &mut height,
                &mut generation,
            )
        };

        assert_eq!(required, 8);
        assert_eq!((width, height), (2, 1));
        assert!(generation > 0);

        let mut bytes = vec![0; required];
        let copied = unsafe {
            fresh_builder_copy_latest_frame(
                bytes.as_mut_ptr(),
                bytes.len(),
                &mut width,
                &mut height,
                &mut generation,
            )
        };
        assert_eq!(copied, 8);
        assert_eq!(bytes, vec![1, 2, 3, 4, 5, 6, 7, 8]);

        fresh_builder_frame_capture_enabled(false);
    }
}
