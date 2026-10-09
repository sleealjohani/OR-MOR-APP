# From the real café to the in-app 3D scene

The prototype's café is built in code (`CafeSceneBuilder`) so we could perfect camera motion first.
To get a photoreal environment, scan the café and drop the model in. The camera system, hotspots
and panels stay the same.

## 1. Capture

Use an iPhone Pro (it has LiDAR) after closing time, with all the usual lights on: cove LEDs,
ceiling strips and the sign.

* **Apps**: Polycam or Scaniverse (room scan with photo texture), or Apple's Object Capture via
  Reality Composer Pro for individual hero objects such as a table set and the counter.
* Walk slowly and cover each area from several heights: the entrance and exterior, the seating,
  the counter and display case, and the management area.
* Capture hero objects separately at higher detail: one table with its chairs, and the counter front
  with the crest. Instance the table set in code.
* Avoid people, and keep the glass doors open or shut consistently.

## 2. Clean up (Blender or Reality Composer Pro)

* Scale to **metres**. Origin at floor level, centred on the doorway. **−Z points into the café** and
  +X to the right when facing the doors from the street (the same axes as `CafeLayout`).
* Decimate to roughly **150–300k triangles in total**. Bake textures into 2–4 atlases of 2048 px,
  then export as **USDZ**.
* Remove the scanned doors and keep them as separate objects so they can swing open.

## 3. Name the interactive parts

The app finds interactive objects by name. Add empty or parent nodes:

| Node name | What it wraps | Notes |
| --- | --- | --- |
| `hotspot:table-1`, `hotspot:table-2`, … | each table and its chairs | Origin at the floor under the tabletop centre |
| `hotspot:cashier` | counter and display case | |
| `hotspot:management` | management desk or door | |
| `door_left`, `door_right` | door leaves | Pivot on the hinge |

Then update `CafeLayout.tables`, `counterCenter` and `managementDesk` to match. The camera poses
derive from those values.

## 4. Load it

In `CafeSceneView.Coordinator.attach`, replace `CafeSceneBuilder.build()` with a loader that does
the following:

1. Loads the USDZ with `try await Entity(named: "ORMOR_Cafe")`.
2. Adds a `CollisionComponent` to each `hotspot:*` node, using the bounds of its visual model.
3. Wires the door pivots and hotspot rings as the builder does today.

Keep the primitive builder as an offline / low-memory fallback.

## Alternative: Gaussian splats

Splat captures (for example from Luma or Polycam) look the most photoreal, but RealityKit does not
render them natively. They would need a Metal splat renderer composited under SwiftUI. Revisit this
if the mesh scan is not convincing enough. The camera path code is renderer-independent.
