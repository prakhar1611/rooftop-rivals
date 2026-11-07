#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# An explicitly supplied compiler wins; a valid JDK17+ on PATH is sufficient.
if [[ -n "${JAVAC:-}" ]]; then
  COMPILER="$JAVAC"
elif [[ -n "${JAVA_HOME:-}" ]]; then
  COMPILER="$JAVA_HOME/bin/javac"
else
  COMPILER="$(command -v javac || true)"
  MAJOR=$("${COMPILER:-false}" -version 2>&1 | sed -nE 's/^javac ([0-9]+).*/\1/p' || true)
  if [[ -z "$MAJOR" || "$MAJOR" -lt 17 ]]; then
    echo "A JDK17+ compiler is required. Set JAVAC or JAVA_HOME, or install javac on PATH." >&2; exit 1
  fi
fi
if [[ ! -x "$COMPILER" ]] && ! command -v "$COMPILER" >/dev/null 2>&1; then
  echo 'A JDK17+ compiler is required. Set JAVAC or JAVA_HOME, or install javac on PATH.' >&2; exit 1
fi
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/classes" build
CP=$(python3 - <<'PY'
import pathlib,os
print(os.pathsep.join(str(p) for p in sorted(pathlib.Path('deps').glob('*.jar'))))
PY
)
# Android APIs come from the published compile-only Android framework jar.
"$COMPILER" -source 17 -target 17 -Xlint:deprecation -cp "$CP" -d "$WORK/classes" $(find src/main/java -name '*.java')
python3 - "$WORK" <<'PY'
import hashlib,io,pathlib,sys,zipfile
work=pathlib.Path(sys.argv[1])
def put(z,name,data):
 info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;z.writestr(info,data)
classes=io.BytesIO()
with zipfile.ZipFile(classes,'w') as z:
 for p in sorted((work/'classes').rglob('*.class')):put(z,p.relative_to(work/'classes').as_posix(),p.read_bytes())
manifest=pathlib.Path('src/main/AndroidManifest.xml').read_text().replace('<manifest ','<manifest package="org.rooftoprivals.services" ',1)
manifest=manifest.replace('  <application>','  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36" />\n  <application>',1)
out=pathlib.Path('build/kite-google-services.aar')
with zipfile.ZipFile(out,'w') as z:
 put(z,'classes.jar',classes.getvalue());put(z,'AndroidManifest.xml',manifest.encode())
 put(z,'proguard.txt',pathlib.Path('consumer-rules.pro').read_bytes());put(z,'R.txt',b'')
pathlib.Path('build/SHA256SUMS').write_text(hashlib.sha256(out.read_bytes()).hexdigest()+'  '+str(out)+'\n')
PY
