#!/usr/bin/env python3
"""Regenerates the geometry in scenes/arena.tscn from scripts/config.gd.

Keeps everything that was tuned by hand — environment, sky, materials,
lights — and rewrites only the box sub-resources and the floor, wall and
cover nodes, so the arena's size lives in one constant.

    python3 tools/generate_arena.py
"""
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "config.gd"
SCENE = ROOT / "scenes" / "arena.tscn"


def const(name: str) -> float:
    match = re.search(rf"^const {name} := ([\d.]+)", CONFIG.read_text(), re.M)
    if not match:
        raise SystemExit(f"{name} not found in config.gd")
    return float(match.group(1))


def fmt(value: float) -> str:
    return repr(round(float(value), 6))


def main() -> None:
    half = const("ARENA_HALF_EXTENT")
    wall_h = const("WALL_HEIGHT")
    wall_t = const("WALL_THICKNESS")

    # (name, centre, full size, material)
    blocks = [("Floor", (0.0, -0.25, 0.0), (half * 2, 0.5, half * 2), "floor")]
    edge = half + wall_t * 0.5
    span = half * 2 + wall_t * 2
    blocks += [
        ("WallNorth", (0.0, wall_h / 2, -edge), (span, wall_h, wall_t), "wall"),
        ("WallSouth", (0.0, wall_h / 2, edge), (span, wall_h, wall_t), "wall"),
        ("WallWest", (-edge, wall_h / 2, 0.0), (wall_t, wall_h, span), "wall"),
        ("WallEast", (edge, wall_h / 2, 0.0), (wall_t, wall_h, span), "wall"),
    ]
    # Cover as fractions of the half extent, so it scales with the arena.
    # Symmetric so no spawn point is advantaged.
    cover = [
        ("CoverCentre", (0.0, 0.0), (2.5, 1.5, 2.5)),
        ("CoverWest", (-0.42, -0.17), (1.2, 1.2, 3.0)),
        ("CoverEast", (0.42, 0.17), (1.2, 1.2, 3.0)),
        ("CoverNorth", (0.17, -0.46), (3.0, 1.2, 1.2)),
        ("CoverSouth", (-0.17, 0.46), (3.0, 1.2, 1.2)),
    ]
    for name, (fx, fz), h in cover:
        blocks.append((name, (fx * half, h[1], fz * half), (h[0] * 2, h[1] * 2, h[2] * 2), "cover"))

    sizes, size_id, size_material = [], {}, {}
    for _, _, size, material in blocks:
        if size not in size_id:
            size_id[size] = f"Box_{len(sizes)}"
            sizes.append(size)
            size_material[size] = material

    scene = SCENE.read_text()
    prelude = scene[: scene.index('[sub_resource type="BoxMesh"')]
    nodes_start = scene.index('[node name="Arena"')
    nodes_end = scene.index('[node name="Floor"')
    fixed_nodes = scene[nodes_start:nodes_end]

    out = [prelude.rstrip("\n"), ""]
    for size in sizes:
        sid = size_id[size]
        out += [
            f'[sub_resource type="BoxMesh" id="Mesh_{sid}"]',
            f'material = SubResource("Material_{size_material[size]}")',
            f"size = Vector3({fmt(size[0])}, {fmt(size[1])}, {fmt(size[2])})",
            "",
            f'[sub_resource type="BoxShape3D" id="Shape_{sid}"]',
            f"size = Vector3({fmt(size[0])}, {fmt(size[1])}, {fmt(size[2])})",
            "",
        ]
    out.append(fixed_nodes.rstrip("\n"))
    out.append("")
    for name, centre, size, _ in blocks:
        sid = size_id[size]
        origin = ", ".join(fmt(v) for v in centre)
        out += [
            f'[node name="{name}" type="StaticBody3D" parent="."]',
            f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {origin})",
            "collision_layer = 1",
            "collision_mask = 0",
            "",
            f'[node name="Mesh" type="MeshInstance3D" parent="{name}"]',
            f'mesh = SubResource("Mesh_{sid}")',
            "",
            f'[node name="Collision" type="CollisionShape3D" parent="{name}"]',
            f'shape = SubResource("Shape_{sid}")',
            "",
        ]
    text = "\n".join(out)
    steps = text.count("[ext_resource ") + text.count("[sub_resource ") + 1
    text = re.sub(r"^\[gd_scene load_steps=\d+ format=3\]", f"[gd_scene load_steps={steps} format=3]", text, flags=re.M)
    SCENE.write_text(text)
    print(f"arena.tscn: half extent {half:g}m, {len(blocks)} blocks, {len(sizes)} sizes, load_steps={steps}")


if __name__ == "__main__":
    main()
