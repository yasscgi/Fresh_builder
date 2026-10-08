use crate::{GpuAdapterInfo, GpuContext, GpuScene, Mat4, MeshPipeline, RenderScene};

const DEFAULT_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8UnormSrgb;

struct ViewportTarget {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    depth_texture: wgpu::Texture,
    depth_view: wgpu::TextureView,
}

pub struct ViewportRenderer {
    context: GpuContext,
    target: ViewportTarget,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    pipeline: MeshPipeline,
}

impl ViewportRenderer {
    pub async fn new(width: u32, height: u32) -> Result<Self, String> {
        validate_extent(width, height)?;
        let context = GpuContext::new().await?;
        let format = DEFAULT_FORMAT;
        let target = create_target(&context.device, width, height, format);
        let pipeline = MeshPipeline::new(&context.device, format);

        Ok(Self {
            context,
            target,
            width,
            height,
            format,
            pipeline,
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

    pub fn upload_scene(&self, scene: &RenderScene) -> Result<GpuScene, String> {
        self.context.upload_scene(
            scene,
            &self.pipeline.joint_palette_bind_group_layout,
            &self.pipeline.model_bind_group_layout,
        )
    }

    pub fn set_scene_model_transform(
        &self,
        scene: &mut GpuScene,
        translation: [f32; 3],
        rotation_xyz: [f32; 3],
        scale: f32,
    ) -> Result<(), String> {
        scene.set_model_transform(
            &self.context.queue,
            translation,
            rotation_xyz,
            scale,
        )
    }

    pub fn apply_scene_two_bone_solution(
        &self,
        scene: &mut GpuScene,
        upper: usize,
        lower: usize,
        end: usize,
        solved_mid: [f32; 3],
        solved_end: [f32; 3],
    ) -> Result<(), String> {
        scene.apply_two_bone_solution(
            &self.context.queue,
            upper,
            lower,
            end,
            solved_mid,
            solved_end,
        )
    }

    pub fn set_scene_joint_local_matrix(
        &self,
        scene: &mut GpuScene,
        joint_index: usize,
        matrix: Mat4,
    ) -> Result<(), String> {
        scene.set_joint_local_matrix(&self.context.queue, joint_index, matrix)
    }

    pub fn set_scene_joint_euler_xyz(
        &self,
        scene: &mut GpuScene,
        joint_index: usize,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<(), String> {
        scene.set_joint_local_euler_xyz(&self.context.queue, joint_index, x, y, z)
    }

    pub fn set_scene_hand_open(
        &self,
        scene: &mut GpuScene,
        open_amount: f32,
    ) -> Result<usize, String> {
        scene.set_hand_open(&self.context.queue, open_amount)
    }

    pub fn reset_scene_pose(&self, scene: &mut GpuScene) -> Result<(), String> {
        scene.reset_pose(&self.context.queue)
    }

    pub fn render_scenes(
        &self,
        scenes: &[&GpuScene],
        view_projection: [[f32; 4]; 4],
        rgba: [f64; 4],
    ) {
        self.pipeline
            .write_camera(&self.context.queue, &view_projection);

        let mut encoder = self
            .context
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Fresh Builder Scene Encoder"),
            });

        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Fresh Builder Scene Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
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
                })],
                depth_stencil_attachment: Some(
                    wgpu::RenderPassDepthStencilAttachment {
                        view: &self.target.depth_view,
                        depth_ops: Some(wgpu::Operations {
                            load: wgpu::LoadOp::Clear(1.0),
                            store: wgpu::StoreOp::Store,
                        }),
                        stencil_ops: None,
                    },
                ),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });

            pass.set_pipeline(&self.pipeline.pipeline);
            pass.set_bind_group(0, &self.pipeline.camera_bind_group, &[]);

            for scene in scenes {
                pass.set_bind_group(1, &scene.joint_palette_bind_group, &[]);
                pass.set_bind_group(2, &scene.model_bind_group, &[]);
                for mesh in &scene.meshes {
                    pass.set_vertex_buffer(0, mesh.vertex_buffer.slice(..));
                    pass.set_index_buffer(
                        mesh.index_buffer.slice(..),
                        wgpu::IndexFormat::Uint32,
                    );
                    pass.draw_indexed(0..mesh.index_count, 0, 0..1);
                }
            }
        }

        self.context.queue.submit(Some(encoder.finish()));
    }

    pub fn read_rgba8(&self) -> Result<Vec<u8>, String> {
        let unpadded_bytes_per_row = self.width as usize * 4;
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT as usize;
        let padded_bytes_per_row =
            (unpadded_bytes_per_row + align - 1) / align * align;
        let buffer_size = padded_bytes_per_row
            .checked_mul(self.height as usize)
            .ok_or_else(|| "Viewport readback size overflow".to_owned())?;

        let buffer = self.context.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Fresh Builder Viewport Readback"),
            size: buffer_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        let mut encoder = self
            .context
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Fresh Builder Viewport Readback Encoder"),
            });

        encoder.copy_texture_to_buffer(
            self.target.texture.as_image_copy(),
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded_bytes_per_row as u32),
                    rows_per_image: Some(self.height),
                },
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );

        let submission = self.context.queue.submit([encoder.finish()]);
        let slice = buffer.slice(..);
        let (sender, receiver) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });

        self.context
            .device
            .poll(wgpu::PollType::Wait {
                submission_index: Some(submission),
                timeout: Some(std::time::Duration::from_secs(2)),
            })
            .map_err(|error| format!("Viewport readback poll failed: {error:?}"))?;

        receiver
            .recv_timeout(std::time::Duration::from_secs(2))
            .map_err(|_| "Viewport readback timed out".to_owned())?
            .map_err(|error| format!("Viewport buffer map failed: {error}"))?;

        let mapped = slice.get_mapped_range();
        let mut pixels =
            Vec::with_capacity(unpadded_bytes_per_row * self.height as usize);
        for row in mapped.chunks(padded_bytes_per_row).take(self.height as usize) {
            pixels.extend_from_slice(&row[..unpadded_bytes_per_row]);
        }
        drop(mapped);
        buffer.unmap();

        Ok(pixels)
    }

    pub fn read_depth32f(&self) -> Result<Vec<f32>, String> {
        let bytes_per_pixel = std::mem::size_of::<f32>();
        let unpadded_bytes_per_row = self.width as usize * bytes_per_pixel;
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT as usize;
        let padded_bytes_per_row =
            (unpadded_bytes_per_row + align - 1) / align * align;
        let buffer_size = padded_bytes_per_row
            .checked_mul(self.height as usize)
            .ok_or_else(|| "Viewport depth readback size overflow".to_owned())?;

        let buffer = self.context.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Fresh Builder Depth Readback"),
            size: buffer_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        let mut encoder = self
            .context
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Fresh Builder Depth Readback Encoder"),
            });

        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo {
                texture: &self.target.depth_texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::DepthOnly,
            },
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout {
                    offset: 0,
                    bytes_per_row: Some(padded_bytes_per_row as u32),
                    rows_per_image: Some(self.height),
                },
            },
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );

        let submission = self.context.queue.submit([encoder.finish()]);
        let slice = buffer.slice(..);
        let (sender, receiver) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            let _ = sender.send(result);
        });

        self.context
            .device
            .poll(wgpu::PollType::Wait {
                submission_index: Some(submission),
                timeout: Some(std::time::Duration::from_secs(2)),
            })
            .map_err(|error| format!("Depth readback poll failed: {error:?}"))?;

        receiver
            .recv_timeout(std::time::Duration::from_secs(2))
            .map_err(|_| "Depth readback timed out".to_owned())?
            .map_err(|error| format!("Depth buffer map failed: {error}"))?;

        let mapped = slice.get_mapped_range();
        let mut depth = Vec::with_capacity(self.width as usize * self.height as usize);
        for row in mapped.chunks(padded_bytes_per_row).take(self.height as usize) {
            for chunk in row[..unpadded_bytes_per_row].chunks_exact(bytes_per_pixel) {
                depth.push(f32::from_ne_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
            }
        }
        drop(mapped);
        buffer.unmap();
        Ok(depth)
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
    let depth_texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("Fresh Builder Viewport Depth"),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Depth32Float,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let depth_view =
        depth_texture.create_view(&wgpu::TextureViewDescriptor::default());

    ViewportTarget {
        texture,
        view,
        depth_texture,
        depth_view,
    }
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
