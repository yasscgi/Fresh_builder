use crate::{GpuAdapterInfo, GpuContext};

const DEFAULT_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8UnormSrgb;

struct ViewportTarget {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
}

pub struct ViewportRenderer {
    context: GpuContext,
    target: ViewportTarget,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
}

impl ViewportRenderer {
    pub async fn new(width: u32, height: u32) -> Result<Self, String> {
        validate_extent(width, height)?;
        let context = GpuContext::new().await?;
        let format = DEFAULT_FORMAT;
        let target = create_target(&context.device, width, height, format);

        Ok(Self {
            context,
            target,
            width,
            height,
            format,
        })
    }

    pub fn adapter_info(&self) -> &GpuAdapterInfo {
        &self.context.info
    }

    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    pub fn resize(&mut self, width: u32, height: u32) -> Result<(), String> {
        validate_extent(width, height)?;

        if self.width == width && self.height == height {
            return Ok(());
        }

        self.target = create_target(&self.context.device, width, height, self.format);
        self.width = width;
        self.height = height;
        Ok(())
    }

    pub fn render_clear(&self, rgba: [f64; 4]) {
        let mut encoder = self
            .context
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Fresh Builder Viewport Encoder"),
            });

        let color_attachment = Some(wgpu::RenderPassColorAttachment {
            view: &self.target.view,
            depth_slice: None,
            resolve_target: None,
            ops: wgpu::Operations {
                load: wgpu::LoadOp::Clear(wgpu::Color {
                    r: rgba[0].clamp(0.0, 1.0),
                    g: rgba[1].clamp(0.0, 1.0),
                    b: rgba[2].clamp(0.0, 1.0),
                    a: rgba[3].clamp(0.0, 1.0),
                }),
                store: wgpu::StoreOp::Store,
            },
        });
        let color_attachments = [color_attachment];

        {
            let _pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Fresh Builder Viewport Clear"),
                color_attachments: &color_attachments,
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
        }

        self.context.queue.submit(Some(encoder.finish()));
    }

    pub fn texture(&self) -> &wgpu::Texture {
        &self.target.texture
    }
}

fn create_target(
    device: &wgpu::Device,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
) -> ViewportTarget {
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("Fresh Builder Viewport Target"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });

    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

    ViewportTarget { texture, view }
}

fn validate_extent(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Err("Viewport width and height must be greater than zero".to_owned());
    }
    if width > 16_384 || height > 16_384 {
        return Err("Viewport extent exceeds the Fresh Builder safety limit".to_owned());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::validate_extent;

    #[test]
    fn rejects_zero_and_unbounded_viewports() {
        assert!(validate_extent(0, 100).is_err());
        assert!(validate_extent(100, 0).is_err());
        assert!(validate_extent(16_385, 100).is_err());
        assert!(validate_extent(1920, 1080).is_ok());
    }
}
