#!/bin/bash

set -euo pipefail

OPENWRT_DIR="${OPENWRT_DIR:-$(pwd)}"
REPO_DIR="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"

DTS="$OPENWRT_DIR/target/linux/mediatek/dts-ext/mt7986a-clx-s20l.dts"
IMAGE_MK="$OPENWRT_DIR/target/linux/mediatek/image/filogic-ext.mk"

[ -f "$DTS" ] || {
    echo "ERROR: missing DTS: $DTS" >&2
    exit 1
}
[ -f "$IMAGE_MK" ] || {
    echo "ERROR: missing image Makefile: $IMAGE_MK" >&2
    exit 1
}

# The vendor firmware identifies this board as supergateway,s20l, while the
# 25.12 source uses clx,s20l. Keep both identities so sysupgrade accepts the
# existing installation and future images remain compatible with CLX builds.
python3 - "$DTS" "$IMAGE_MK" "$OPENWRT_DIR" <<'PY'
from pathlib import Path
import sys

dts = Path(sys.argv[1])
image_mk = Path(sys.argv[2])
openwrt = Path(sys.argv[3])

text = dts.read_text()
text = text.replace(
    'model = "CLX S20L";',
    'model = "Super Gateway S20L";',
)
text = text.replace(
    'compatible = "clx,s20l", "mediatek,mt7986a";',
    'compatible = "supergateway,s20l", "clx,s20l", "mediatek,mt7986a";',
)
dts.write_text(text)

text = image_mk.read_text()
needle = """define Device/clx_s20l
  $(call Device/clx_s20-common)
  DEVICE_MODEL := S20L
  DEVICE_DTS := mt7986a-clx-s20l
endef
"""
replacement = """define Device/clx_s20l
  $(call Device/clx_s20-common)
  DEVICE_MODEL := S20L
  DEVICE_DTS := mt7986a-clx-s20l
  SUPPORTED_DEVICES += supergateway,s20l clx,s20l
endef
"""
if "SUPPORTED_DEVICES += supergateway,s20l clx,s20l" not in text:
    if needle not in text:
        raise SystemExit("clx_s20l device block changed upstream")
    image_mk.write_text(text.replace(needle, replacement, 1))

board_files = [
    openwrt / "target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh",
    openwrt / "target/linux/mediatek/filogic/base-files/etc/board.d/01_leds",
    openwrt / "target/linux/mediatek/filogic/base-files/etc/board.d/02_network",
    openwrt / "target/linux/mediatek/filogic/base-files/etc/hotplug.d/net/09-fix-mtwifi-mac",
]

for path in board_files:
    text = path.read_text()
    if "supergateway,s20l" in text:
        continue
    old = "clx,s20l|\\"
    new = "supergateway,s20l|\\\n\tclx,s20l|\\"
    if old not in text:
        raise SystemExit(f"board pattern not found in {path}")
    path.write_text(text.replace(old, new))
PY

# Add the public DaeUniverse APK feed and trust key to the image. This makes
# "apk add honk@daeuniverse ..." possible immediately after the first boot.
if [ -d "$REPO_DIR/25.12/files" ]; then
    mkdir -p "$OPENWRT_DIR/files"
    cp -a "$REPO_DIR/25.12/files/." "$OPENWRT_DIR/files/"
fi

# Keep the existing LAN address stable. The upstream S20L scripts in this
# repository change it to 192.168.2.1; this build intentionally avoids that.
[ -f "$OPENWRT_DIR/package/base-files/files/bin/config_generate" ] || {
    echo "ERROR: package/base-files config_generate is missing" >&2
    exit 1
}

echo "S20L compatibility and APK feed patches applied."
