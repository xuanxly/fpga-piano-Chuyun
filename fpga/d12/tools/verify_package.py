"""校验整理版文件清单；文件被用户修改后，不匹配是预期结果。"""
from pathlib import Path
import hashlib
import sys

root = Path(__file__).resolve().parents[1]
manifest = root / "SHA256SUMS.txt"
if not manifest.is_file():
    raise SystemExit("找不到 SHA256SUMS.txt")

count = 0
problems = []
for line in manifest.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    expected, relative = line.split("  ", 1)
    path = root / relative
    if not path.is_file():
        problems.append(f"缺少：{relative}")
        continue
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest().upper()
    if actual != expected.upper():
        problems.append(f"已修改：{relative}")
    count += 1

if problems:
    print("\n".join(problems))
    print(f"校验未通过：{len(problems)} 个文件与整理时不同。")
    sys.exit(1)
print(f"PASS：{count} 个文件与整理时完全一致。")
