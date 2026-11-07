#!/usr/bin/env python3
"""Fetch published compile inputs; no Android SDK license acceptance."""
import hashlib,json,pathlib,urllib.request,zipfile,concurrent.futures
ROOT=pathlib.Path(__file__).resolve().parent
(ROOT/'deps').mkdir(parents=True,exist_ok=True)
(ROOT/'build').mkdir(parents=True,exist_ok=True)
G='https://dl.google.com/dl/android/maven2/'
M='https://repo.maven.apache.org/maven2/'
coords=[
(G,'com.google.android.gms','play-services-ads','25.5.0','aar'),
(G,'com.google.android.gms','play-services-ads-api','25.5.0','aar'),
(G,'com.google.android.gms','play-services-basement','18.9.0','aar'),
(G,'com.google.android.gms','play-services-tasks','18.2.0','aar'),
(G,'com.google.android.ump','user-messaging-platform','4.0.0','aar'),
(G,'androidx.credentials','credentials','1.6.0','aar'),
(G,'androidx.credentials','credentials-play-services-auth','1.6.0','aar'),
(G,'com.google.android.libraries.identity.googleid','googleid','1.2.1','aar'),
(G,'androidx.annotation','annotation-jvm','1.9.1','jar'),
(M,'org.jetbrains.kotlin','kotlin-stdlib','2.0.21','jar'),
(M,'org.jetbrains','annotations','23.0.0','jar'),
(M,'org.godotengine','godot','4.6.3.stable','aar'),
(M,'org.robolectric','android-all','14-robolectric-10818077','jar')]
def get(c):
 base,g,a,v,ext=c; url=base+g.replace('.','/')+'/'+a+'/'+v+'/'+a+'-'+v+'.'+ext
 dest=ROOT/'deps'/url.rsplit('/',1)[-1]
 if not dest.exists():
  with urllib.request.urlopen(url,timeout=120) as r: dest.write_bytes(r.read())
 if ext=='aar':
  with zipfile.ZipFile(dest) as z: (ROOT/'deps'/(a+'-'+v+'-classes.jar')).write_bytes(z.read('classes.jar'))
 print(dest.name,flush=True)
 return {'coordinate':f'{g}:{a}:{v}','url':url,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'compile_only':a in ['godot','android-all']}
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: results=list(pool.map(get,coords))
(ROOT/'build/dependency-provenance.json').write_text(json.dumps(results,indent=2)+'\n')
