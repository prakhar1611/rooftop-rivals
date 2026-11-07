#!/usr/bin/env python3
"""Static contract checks; not substitutes for device SDK integration tests."""
from pathlib import Path
import re,zipfile
p=Path(__file__).resolve().parent
s=(p/'src/main/java/org/rooftoprivals/services/KiteGoogleServices.java').read_text()
m=(p/'src/main/AndroidManifest.xml').read_text()
assert set(re.findall(r'ca-app-pub-[\d~/]+',s+m))=={'ca-app-pub-3940256099942544/5224354917','ca-app-pub-3940256099942544~3347511713'}
assert 'public boolean is_reward_verified(long id,String transaction){return false;}' in s
assert 'setTagForUnderAgeOfConsent(false)' in s and 'return adult&&outside&&opted;' in s
assert s.index('consent.requestConsentInfoUpdate')<s.index('UserMessagingPlatform.loadConsentForm')<s.index('MobileAds.initialize(')
assert 'if(error!=null||!consent.canRequestAds())' in s
assert 'ad.show(getActivity(),reward->{if(current(generation))earned[0]=true;});' in s
assert 'adGeneration++;loaded=null;' in s
assert 'Log.' not in s and 'SharedPreferences' not in s
assert 'DELAY_APP_MEASUREMENT_INIT' in m and 'tools:node="remove"' in m
assert 'MobileAdsInitProvider' in m
with zipfile.ZipFile(p/'build/kite-google-services.aar') as z:
 assert 'classes.jar' in z.namelist() and 'AndroidManifest.xml' in z.namelist()
 packaged=z.read('AndroidManifest.xml').decode()
 assert 'package="org.rooftoprivals.services"' in packaged
 assert 'android:minSdkVersion="24" android:targetSdkVersion="36"' in packaged
assert 'if(!showing&&!consentPresenting)invalidateAds()' in s
assert 'long cancelled=pendingTestId;pendingTestId=-1;' in s
assert 'if(cancelled>=0)emitSignal("test_reward_result",cancelled,false' in s
assert 'form.show(getActivity()' in s and 'loadAndShowConsentFormIfRequired' not in s

for permission in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'READ_PHONE_STATE', 'ACCESS_ADSERVICES_AD_ID', 'ACCESS_ADSERVICES_ATTRIBUTION', 'ACCESS_ADSERVICES_TOPICS', 'USE_BIOMETRIC', 'USE_FINGERPRINT', 'FOREGROUND_SERVICE']:
 assert f'android.permission.{permission}" tools:node="remove"' in m
assert 'androidx.work.impl.foreground.SystemForegroundService" tools:node="remove"' in m

print('PASS: source, lifecycle, permission-removal and packaged-manifest assertions (not real-device tests).')
