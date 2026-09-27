{{flutter_js}}
{{flutter_build_config}}

// GitHub Pages can cache main.dart.js independently from index.html. Give the
// generated entry point an explicit release version so deployments never mix
// an old application bundle with a new page.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath = `${build.mainJsPath}?v=20260927-2`;
  }
}

_flutter.loader.load();
