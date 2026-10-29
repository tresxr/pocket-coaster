# Aureole

A native, fully three-dimensional miniature world for Android, built with **Godot 4.6.3**. Amber dunes meet a tidal lagoon beneath a curled aragonite crest and a brass astronomical gate. Rounded forests, a lighthouse sanctuary, a caravan, coral, mushrooms, exposed strata, interlocking chains and a gliding sky ray reward close inspection.

![Native Godot hero frame](docs/hero.png)

The existing Pocket Coaster browser game at the repository root remains independently runnable.

## Run and install

Open `project.godot` in Godot **4.6.3**. From the repository root, import once with `godot --headless --editor --path aureole --import`, then run `godot --path aureole`. No Blender installation is needed to run or export the committed project.

The **Aureole Android** GitHub Actions workflow imports the project, checks scripts, runs interaction/lifecycle smoke tests, renders a native screenshot, exports an ARM64 debug APK and verifies its signature. Download **Aureole-Android-debug** from a successful run, unzip it and install `aureole-debug.apk` on the phone. Android may require enabling installation from the application used to open the APK. Debug builds are for sideloading; the generated debug key is disposable and is not a Play Store signing identity.

For a local Android build, install JDK 17+, Android SDK platform tools, build tools **36.0.0**, platform **36**, Godot 4.6.3 and the matching export templates:

```sh
cd aureole
python3 tools/configure_android.py --sdk /path/to/android-sdk --java /path/to/jdk
godot --headless --editor --import
mkdir -p build
godot --headless --export-debug Android build/aureole-debug.apk
```

The standard Godot Android template supplies minimum SDK 24 and target SDK 36. This export uses the template APK directly; Gradle and remote dependencies are not needed for application compilation. No network, storage, microphone or account permission is requested by Aureole.

## Explore

- Drag one finger to orbit; release for gentle momentum.
- Pinch with two fingers to zoom. Desktop: drag and use the wheel.
- Wait eight seconds for a slow cinematic orbit.
- The discreet `···` control opens quality, automatic orbit and initial-view settings.
- Android Back closes settings first, then saves and exits. Camera and preferences also save on focus loss/pause and restore at launch.

## Visual and rendering architecture

`tools/generate_world.py` is the deterministic offline art workshop (seed **41027**). It emits eight small glTF assets plus a placement atlas. Rebuild with Blender 4.3+:

```sh
cd aureole
blender -b --python tools/generate_world.py -- --output assets/generated
```

The displaced closed globe shares its geography with the water patch, dune crests, shoreline, strata, vegetation and navigation trail. The crest is a ribbed spline sweep with mineral fans and faceted crystal outgrowths. The gate contains concentric machined rings, exposed bolts, radial markers, emissive inlays, support struts and an armillary core. All major forms are custom meshes. Vertex pigments carry biome gradients and material variation without a large texture set.

The scene uses GLES3 / Compatibility for broad Android support, restrained linear-light exposure, one shadowed warm key, cool fill and lunar rim, an atmospheric procedural sky, animated water normals and low-amplitude foliage motion. Contact comes from geometry intersections, vertex shading and the key shadow. Expensive screen-space ambient occlusion, volumetrics and bloom are intentionally absent from this mobile rendering path. Metal, crystal, sand, stone, bark, vegetation and water have separate roughness/specular responses.

1,110 atlas placements are consolidated into **eight MultiMesh material batches**: 303 trees, 655 stones and 152 grass clumps. The static diorama uses 13 material batches; clouds use four shared-mesh batches, stars use one and 18 orbital motes share one. The imported meshes have generated LODs and native bounding-box/frustum culling. `world.glb` contains 170,524 triangles before importer simplification; trees share their meshes and materials. There are no transparent water layers or full-screen postprocess effects.

Adaptive quality starts at Cinematic, lowers sampling after four seconds above 20.5 ms/frame, and only restores quality after 22 seconds below 17.3 ms/frame. A twelve-second cooldown prevents oscillation. Presets use 100% / 85% / 70% internal resolution, 4× / 2× / no MSAA, increasing LOD thresholds and reduced shadow cost. Battery saver caps rendering at 30 FPS. The diorama's central geometry remains present at every level. Frame monitoring excludes pause intervals and clamps long stalls. Android controls scale with display density and avoid display cutouts.

## Validation and limits

```sh
cd aureole
godot --headless --audio-driver Dummy -- --smoke-test
# With an X server, or use xvfb-run -a on Linux:
mkdir -p build
AUREOLE_CAPTURE_PATH="$PWD/build/hero.png" godot --audio-driver Dummy -- --capture
```

The smoke test covers assembly, noncontiguous touch IDs, pinch response, gesture cancellation, quality presets, adaptive response, settings persistence and pause/resume. `tools/check_log.py` fails CI on script, shader and runtime errors even if Godot exits with status zero. The artifact includes import/render/export logs, the signed APK, SHA-256, package metadata and a real Godot hero capture.

No `reference/concept.jpg` was supplied in the accessible repositories or workspace; the scene follows the written art direction. Galaxy A56 frame rate, thermal stability, vendor-driver behavior and Android process recreation need physical-device testing. Desktop software rendering is used for visual inspection and is not a mobile performance benchmark. This is an intentionally silent contemplative experience.

Cormorant Garamond is bundled under the SIL Open Font License; see `assets/FONT-LICENSE.txt`. Godot is MIT licensed: <https://godotengine.org/license/>. All scene geometry and shaders are generated or authored in this project, with no external environment-art dependencies.
