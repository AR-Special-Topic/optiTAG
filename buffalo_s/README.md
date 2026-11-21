# Local face model weights

Model binaries are intentionally excluded from Git. Before building, obtain the InsightFace `buffalo_s` model pack and place these two files in this directory:

- `det_500m.onnx`
- `w600k_mbf.onnx`

Use weights you are authorized to use, and review the upstream model terms before distributing an App containing them. Other models in the pack are not used by this App.

Validate the expected weights from this directory:

```sh
shasum -a 256 -c SHA256SUMS
```

The checksums identify the weights used during development; model files already present locally are preserved.
