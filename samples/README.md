# Samples for CI decompile smoke test

| File | Size | In git |
|------|------|--------|
| `preload-index.jsc` | ~17 KB | ✅ committed |
| `main-index.jsc` | ~2.2 MB | ❌ gitignored — copy locally before private fork push |

Copy from ldai project:

```powershell
Copy-Item "C:\Users\41645\Desktop\ldai\dt-ai-helper-restored\jscdecompiler-upload\preload-index.jsc" samples\
Copy-Item "C:\Users\41645\Desktop\ldai\dt-ai-helper-restored\jscdecompiler-upload\main-index.jsc" samples\
```

For public forks, keep only `preload-index.jsc` to avoid leaking proprietary bytecode.
