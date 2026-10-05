#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuAdapterInfo {
    pub name: String,
    pub backend: String,
    pub device_type: String,
    pub driver: String,
    pub driver_info: String,
}

pub async fn probe_high_performance_adapter() -> Result<GpuAdapterInfo, String> {
    let instance = wgpu::Instance::default();

    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
            apply_limit_buckets: false,
        })
        .await
        .map_err(|error| format!("No compatible GPU adapter: {error:?}"))?;

    Ok(adapter_info(&adapter))
}

pub struct GpuContext {
    pub instance: wgpu::Instance,
    pub adapter: wgpu::Adapter,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub info: GpuAdapterInfo,
}

impl GpuContext {
    pub async fn new() -> Result<Self, String> {
        let instance = wgpu::Instance::default();

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                compatible_surface: None,
                apply_limit_buckets: false,
            })
            .await
            .map_err(|error| format!("No compatible GPU adapter: {error:?}"))?;

        let info = adapter_info(&adapter);

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor::default())
            .await
            .map_err(|error| format!("Failed to create WGPU device: {error:?}"))?;

        Ok(Self {
            instance,
            adapter,
            device,
            queue,
            info,
        })
    }
}

fn adapter_info(adapter: &wgpu::Adapter) -> GpuAdapterInfo {
    let info = adapter.get_info();

    GpuAdapterInfo {
        name: info.name,
        backend: format!("{:?}", info.backend),
        device_type: format!("{:?}", info.device_type),
        driver: info.driver,
        driver_info: info.driver_info,
    }
}

#[cfg(test)]
mod tests {
    use super::GpuAdapterInfo;

    #[test]
    fn adapter_info_is_platform_neutral_data() {
        let info = GpuAdapterInfo {
            name: "Example GPU".to_owned(),
            backend: "Vulkan".to_owned(),
            device_type: "DiscreteGpu".to_owned(),
            driver: "driver".to_owned(),
            driver_info: "info".to_owned(),
        };

        assert_eq!(info.backend, "Vulkan");
        assert_eq!(info.device_type, "DiscreteGpu");
    }
}
