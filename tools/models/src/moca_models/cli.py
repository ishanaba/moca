import argparse
import hashlib
import json
from pathlib import Path

def checksum(path: Path) -> str:
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""): digest.update(chunk)
    return digest.hexdigest()

def write_manifest(model:Path,output:Path,kind:str):
    if not model.is_file(): raise FileNotFoundError(model)
    output.write_text(json.dumps({"schema":1,"kind":kind,"file":model.name,"sha256":checksum(model)},indent=2)+"\n")

def main():
    parser=argparse.ArgumentParser();sub=parser.add_subparsers(dest="command",required=True)
    manifest=sub.add_parser("manifest");manifest.add_argument("model",type=Path);manifest.add_argument("--kind",required=True,choices=["yolo-pose","rtmpose","rtmo"]);manifest.add_argument("--output",type=Path,required=True)
    export=sub.add_parser("export-yolo");export.add_argument("model");export.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    if args.command=="manifest": write_manifest(args.model,args.output,args.kind)
    else:
        from ultralytics import YOLO
        result=YOLO(args.model).export(format="openvino",half=True,dynamic=False);args.output.write_text(str(result)+"\n")

if __name__=="__main__":main()
