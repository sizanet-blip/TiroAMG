"""Captura pantallas de acceso AMG de TiroAMG."""
from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path

ADB = Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"
OUT = Path(r"d:\Proyectos\flutter\TiroAMG\assets\help")
DUMP = Path.home() / "AppData/Local/Temp/uidump_tiro.xml"
TMP = Path.home() / "AppData/Local/Temp/tiro_shot.png"
PKG = "es.albertomaestre.tiroamg"

OUT.mkdir(parents=True, exist_ok=True)


def adb(*args, timeout=60):
    return subprocess.run([str(ADB), *args], capture_output=True, timeout=timeout)


def dump_ui() -> str:
    adb("shell", "rm", "-f", "/sdcard/uidump.xml")
    adb("shell", "uiautomator", "dump", "/sdcard/uidump.xml")
    adb("pull", "/sdcard/uidump.xml", str(DUMP))
    return DUMP.read_text(encoding="utf-8", errors="ignore")


def nodes(xml: str):
    found = []
    for m in re.finditer(r"<node [^>]*>", xml):
        tag = m.group(0)
        text = re.search(r'text="([^"]*)"', tag)
        desc = re.search(r'content-desc="([^"]*)"', tag)
        bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        label = (desc.group(1) if desc else "") or (text.group(1) if text else "")
        label = label.replace("&#10;", "\n").split("\n")[0].strip()
        if not label or not bounds:
            continue
        x1, y1, x2, y2 = map(int, bounds.groups())
        found.append((label, (x1 + x2) // 2, (y1 + y2) // 2))
    return found


def tap_label(label: str, partial: bool = True) -> bool:
    xml = dump_ui()
    for text, x, y in nodes(xml):
        ok = (label in text) if partial else text == label
        if ok:
            adb("shell", "input", "tap", str(x), str(y))
            time.sleep(1.1)
            return True
    print("NO TAP", label)
    return False


def shot(name: str) -> None:
    dest = OUT / name
    if TMP.exists():
        TMP.unlink()
    subprocess.run(f'"{ADB}" exec-out screencap -p > "{TMP}"', shell=True, check=True)
    data = TMP.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        data = data.replace(b"\r\n", b"\n")
    dest.write_bytes(data)
    print("saved", name, dest.stat().st_size)


def back(n: int = 1) -> None:
    for _ in range(n):
        adb("shell", "input", "keyevent", "4")
        time.sleep(0.55)


def main() -> None:
    adb("shell", "input", "keyevent", "3")
    time.sleep(0.4)
    adb("shell", "am", "force-stop", "com.google.android.calendar")
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(2.5)
    print("labels", [n[0] for n in nodes(dump_ui())][:25])

    tap_label("Entrar")
    time.sleep(0.4)
    shot("25_tiroamg_login.png")

    tap_label("Crear")
    time.sleep(0.5)
    shot("26_tiroamg_registro.png")

    if tap_label("Leer privacidad"):
        time.sleep(0.6)
        shot("27_tiroamg_privacidad.png")
        back()
    if tap_label("Leer condiciones"):
        time.sleep(0.6)
        shot("28_tiroamg_condiciones.png")
        back()

    # Código / recuperar
    if tap_label("digo") or tap_label("digo") or tap_label("Código"):
        time.sleep(0.5)
        shot("29_tiroamg_recuperar.png")
    print("done")


if __name__ == "__main__":
    main()
