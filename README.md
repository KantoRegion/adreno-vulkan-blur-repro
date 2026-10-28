# adreno-vulkan-blur-repro

Minimal Flutter app that reproduces a raster-thread native crash inside the Qualcomm Adreno Vulkan driver (`vulkan.adreno.so`) when Impeller uses its Vulkan backend.

- Upstream issue: [flutter/flutter#192002](https://github.com/flutter/flutter/issues/192002)
- `lib/main.dart` is copied unchanged from the minimal repro posted by [@stephen00001](https://github.com/stephen00001) in [this comment](https://github.com/flutter/flutter/issues/192002#issuecomment-5464966793). Everything else is a stock `flutter create --empty --platforms android` project.

## What it does

The crash needs two things at the same time:

1. A `ui.Picture` that contains about 500 `MaskFilter.blur` draws.
2. That picture replayed inside `saveLayer` offscreens whose bounds change every frame.

## Run

```sh
flutter build apk --release
flutter install
adb logcat -b crash
```

Leave the app in the foreground. It does not need any interaction. The crash goes to the `crash` log buffer.

## Observed on Lenovo TB710FU (Adreno 750)

| | |
|---|---|
| Android | 16, build `BP2A.250605.031.A3` (ZUI 17.5) |
| GPU driver | `V@0762.37 (GIT@346fca22e2)`, 2025-06-03, BuildId `b82ed6457570e060ce70ef441016b975` |
| Flutter | 3.47.7 stable (`abaf9c5237`), engine `d8a2d6c768` |

| Build | Backend | Result |
|---|---|---|
| `--release` | Impeller Vulkan (autoselect) | crash within ~3 s |
| `--profile` + `io.flutter.embedding.android.ImpellerBackend=vulkan` | Impeller Vulkan | crash within ~2 s |
| `--profile` + `io.flutter.embedding.android.ImpellerBackend=opengles` | Impeller OpenGLES | no crash in 90 s |
| `--release` + `io.flutter.embedding.android.EnableImpeller=false` | Skia | no crash in 90 s |

Crash signatures seen across runs (all on `1.raster`):

- `SIGSEGV`, `fault addr 0x1c`, null pointer dereference in `vulkan.adreno.so`, entered through `vkCmdBeginRenderPass` (from `GaussianBlurFilterContents` → `MakeBlurSubpass`) or `vkBeginCommandBuffer`.
- `SIGABRT`, `Scudo ERROR: internal map failure (error desc=Out of memory)`, raised from `calloc` inside `qglinternal::vkCreateFramebuffer`.

At the time of the crash the process had about 17.5k memory mappings, including about 9.8k unnamed anonymous mappings (about 5.9 GB virtual). A production crash with the same `SIGSEGV` signature on the same device showed a similar map (about 14.6k mappings, about 7.7k unnamed anonymous). This suggests the null dereference may be an unchecked allocation failure inside the driver, but that is not confirmed.

The `ImpellerBackend` meta-data only takes effect in debug and profile builds. In release builds the engine always autoselects the backend.
