from moca_models.cli import checksum,write_manifest
import json
def test_manifest(tmp_path):
    model=tmp_path/"model.bin";model.write_bytes(b"moca");output=tmp_path/"model.json";write_manifest(model,output,"yolo-pose")
    data=json.loads(output.read_text());assert data["sha256"]==checksum(model) and data["schema"]==1
