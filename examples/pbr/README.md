# pbr

A 10x5 grid of spheres: roughness left to right, metallic bottom to
top. Deferred PBR with image based lighting from an HDRI environment.

```bash
echoc run -m examples --target pbr
echoc run -m examples --target pbr --define VISU_FINITE
echoc run -m examples --target pbr --define VISU_BACKEND_VULKAN
```

Hold the left mouse button to look, WASD to fly.

## The environment map

`.hdr` files are large and stay out of git. Without one the example
still runs, lit by the sun alone. To get the environment lighting and
the skybox, drop any equirectangular radiance map here:

```bash
mkdir -p examples/pbr/resources/hdri
cp ~/Developer/phpgl/visu/examples/resources/assets/hdri/cowboy_town_saloon_2k.hdr \
   examples/pbr/resources/hdri/
```

Free ones live at https://polyhaven.com/hdris. The example picks up
`cowboy_town_saloon_2k.hdr`; change `HDRI_PATH` in `pbr.eco` for
another name.

## Debug output

`--define VISU_PBR_DUMP` writes the last frame to `var/` (scene,
GBuffer albedo, light pass) so the render can be inspected without a
window.
