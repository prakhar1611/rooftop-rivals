#!/usr/bin/env python3
"""Configure an already-installed official Godot 4.6.3 Android build template.
Does not install software, accept SDK licenses, or configure credentials.
"""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
build=root/'godot/android/build'
config=build/'config.gradle'
if not config.is_file():
    raise SystemExit('Open godot/project.godot in Godot 4.6.3, install matching export templates, then use Project > Install Android Build Template. Run this script afterward.')
s=config.read_text()
if "compileSdk         : 36" not in s:
    raise SystemExit('Unexpected template: expected official Godot 4.6.3 with compileSdk 36. No changes made.')
s,n=re.subn(r"androidGradlePlugin:\s*'[^']+'", "androidGradlePlugin: '8.9.2'",s,count=1)
if n!=1: raise SystemExit('Could not identify Android Gradle plugin version. No changes made.')
config.write_text(s)
p=build/'gradle.properties';s=p.read_text()
for key,value in [('doNotStrip','true'),('android.builder.sdkDownload','false')]:
    s=re.sub(r'^'+re.escape(key)+r'=.*\n?','',s,flags=re.M)
    s+='\n'+key+'='+value+'\n'
p.write_text(s)
(build/'.gdignore').touch()
print('Configured AGP 8.9.2; preserved prebuilt native libraries; disabled automatic SDK package downloads.')
