use builder_render::RenderScene;

pub fn write_3mf(
    scene: &RenderScene,
    path: impl AsRef<std::path::Path>,
) -> Result<(), String> {
    let package = encode_3mf(scene)?;
    std::fs::write(path.as_ref(), package)
        .map_err(|error| format!("Failed to write 3MF {}: {error}", path.as_ref().display()))
}

pub fn encode_3mf(scene: &RenderScene) -> Result<Vec<u8>, String> {
    let model = build_model_xml(scene)?;
    let content_types = br#"<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>"#;
    let rels = br#"<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>"#;

    let files = [
        ("[Content_Types].xml", content_types.as_slice()),
        ("_rels/.rels", rels.as_slice()),
        ("3D/3dmodel.model", model.as_bytes()),
    ];

    encode_store_zip(&files)
}

fn build_model_xml(scene: &RenderScene) -> Result<String, String> {
    if scene.meshes.is_empty() {
        return Err("Cannot encode empty 3MF scene".to_owned());
    }

    let mut out = String::from(
        r#"<?xml version="1.0" encoding="UTF-8"?><model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02"><resources>"#,
    );
    let mut object_id = 1_u32;

    for mesh in &scene.meshes {
        if mesh.indices.len() % 3 != 0 {
            return Err(format!("Mesh {} is not triangulated", mesh.name));
        }
        out.push_str(&format!(r#"<object id="{object_id}" type="model"><mesh><vertices>"#));
        for vertex in &mesh.vertices {
            let [x_m, y_m, z_m] = vertex.position;
            if !x_m.is_finite() || !y_m.is_finite() || !z_m.is_finite() {
                return Err(format!("Mesh {} contains non-finite vertex", mesh.name));
            }
            let x = x_m * 1000.0;
            let y = y_m * 1000.0;
            let z = z_m * 1000.0;
            out.push_str(&format!(r#"<vertex x="{x}" y="{y}" z="{z}"/>"#));
        }
        out.push_str("</vertices><triangles>");
        for triangle in mesh.indices.chunks_exact(3) {
            if triangle.iter().any(|index| *index as usize >= mesh.vertices.len()) {
                return Err(format!("Mesh {} contains invalid triangle index", mesh.name));
            }
            out.push_str(&format!(
                r#"<triangle v1="{}" v2="{}" v3="{}"/>"#,
                triangle[0], triangle[1], triangle[2]
            ));
        }
        out.push_str("</triangles></mesh></object>");
        object_id += 1;
    }

    out.push_str("</resources><build>");
    for id in 1..object_id {
        out.push_str(&format!(r#"<item objectid="{id}"/>"#));
    }
    out.push_str("</build></model>");
    Ok(out)
}

fn encode_store_zip(files: &[(&str, &[u8])]) -> Result<Vec<u8>, String> {
    let mut out = Vec::<u8>::new();
    let mut central = Vec::<CentralEntry>::new();

    for (name, data) in files {
        let offset = out.len() as u32;
        let crc = crc32(data);
        write_u32(&mut out, 0x04034b50);
        write_u16(&mut out, 20);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u32(&mut out, crc);
        write_u32(&mut out, data.len() as u32);
        write_u32(&mut out, data.len() as u32);
        write_u16(&mut out, name.len() as u16);
        write_u16(&mut out, 0);
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(data);

        central.push(CentralEntry {
            name: (*name).to_owned(),
            crc,
            size: data.len() as u32,
            offset,
        });
    }

    let central_offset = out.len() as u32;
    for entry in &central {
        write_u32(&mut out, 0x02014b50);
        write_u16(&mut out, 20);
        write_u16(&mut out, 20);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u32(&mut out, entry.crc);
        write_u32(&mut out, entry.size);
        write_u32(&mut out, entry.size);
        write_u16(&mut out, entry.name.len() as u16);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u16(&mut out, 0);
        write_u32(&mut out, 0);
        write_u32(&mut out, entry.offset);
        out.extend_from_slice(entry.name.as_bytes());
    }
    let central_size = out.len() as u32 - central_offset;

    write_u32(&mut out, 0x06054b50);
    write_u16(&mut out, 0);
    write_u16(&mut out, 0);
    write_u16(&mut out, central.len() as u16);
    write_u16(&mut out, central.len() as u16);
    write_u32(&mut out, central_size);
    write_u32(&mut out, central_offset);
    write_u16(&mut out, 0);

    Ok(out)
}

struct CentralEntry {
    name: String,
    crc: u32,
    size: u32,
    offset: u32,
}

fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffff_u32;
    for byte in data {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }
    !crc
}

fn write_u16(out: &mut Vec<u8>, value: u16) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn write_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;
    use builder_render::{RenderMesh, RenderScene, RenderVertex};

    #[test]
    fn model_xml_exports_engine_meters_as_millimeters() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "unit".into(),
                vertices: vec![
                    RenderVertex { position: [0.1, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 0.1, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 0.0, 0.1], ..RenderVertex::default() },
                ],
                indices: vec![0, 1, 2],
                skinned: false,
            }],
            ..RenderScene::default()
        };

        let xml = build_model_xml(&scene).unwrap();
        assert!(xml.contains(r#"unit="millimeter""#));
        assert!(xml.contains(r#"x="100"#));
        assert!(xml.contains(r#"y="100"#));
        assert!(xml.contains(r#"z="100"#));
    }

    #[test]
    fn emits_zip_container_with_3mf_model() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "triangle".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 1.0, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![0, 1, 2],
                skinned: false,
            }],
            ..RenderScene::default()
        };
        let bytes = encode_3mf(&scene).unwrap();
        assert_eq!(&bytes[..4], &[0x50, 0x4b, 0x03, 0x04]);
        assert!(bytes.windows(b"3D/3dmodel.model".len()).any(|w| w == b"3D/3dmodel.model"));
    }
}
