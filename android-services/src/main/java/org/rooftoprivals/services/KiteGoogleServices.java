package org.rooftoprivals.services;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.CancellationSignal;
import androidx.credentials.*;
import androidx.credentials.exceptions.*;
import com.google.android.libraries.identity.googleid.*;
import com.google.android.gms.ads.*;
import com.google.android.gms.ads.rewarded.*;
import com.google.android.ump.*;
import org.godotengine.godot.Godot;
import org.godotengine.godot.Dictionary;
import org.godotengine.godot.plugin.*;
import java.util.*;
import java.util.concurrent.Executor;
import java.security.SecureRandom;

/** Test-only provider. No production entitlement or token persistence; plugin makes no startup SDK request. */
public final class KiteGoogleServices extends GodotPlugin {
    private static final String TEST_UNIT="ca-app-pub-3940256099942544/5224354917";
    private static final String CLIENT_KEY="org.rooftoprivals.GOOGLE_WEB_CLIENT_ID";
    private final Executor ui = command -> { Activity a=getActivity(); if(a!=null) a.runOnUiThread(command); };
    private boolean adult=false, outside=false, opted=false, initializing=false, initialized=false, showing=false;
    private boolean resumed=false, consentPresenting=false;
    private long adGeneration=0, loginGeneration=0, pendingTestId=-1;
    private CancellationSignal loginCancel;
    private RewardedAd loaded;
    private volatile String publicClientId="";
    public KiteGoogleServices(Godot godot) {
        super(godot);
        try { android.os.Bundle data=getActivity().getPackageManager().getApplicationInfo(getActivity().getPackageName(),PackageManager.GET_META_DATA).metaData;
            if(data!=null) publicClientId=data.getString(CLIENT_KEY,"");
        } catch(Exception ignored) { publicClientId=""; }
    }
    @Override public String getPluginName(){return "KiteGoogleServices";}
    @Override public Set<SignalInfo> getPluginSignals(){return new HashSet<>(Arrays.asList(
        new SignalInfo("login_result",Long.class,Boolean.class),
        new SignalInfo("reward_result",Long.class,String.class),
        new SignalInfo("test_reward_result",Long.class,Boolean.class,String.class),
        new SignalInfo("test_ad_status",String.class)) );}
    @UsedByGodot public void configure_google_sign_in(String clientId){ui.execute(()->{cancelLogin();publicClientId=clientId==null?"":clientId.trim();});}
    @UsedByGodot public Dictionary capabilities(){Dictionary d=new Dictionary();
        d.put("account",publicClientId.endsWith(".apps.googleusercontent.com"));
        d.put("privacy_options",true); d.put("rewarded_ads",false); d.put("test_rewarded_ads",true);
        d.put("label","Google TEST ads / optional Google sign-in"); return d;}
    @UsedByGodot public void set_test_eligibility(boolean isAdult,boolean outsideBattle,boolean optedIn){ui.execute(()->{
        adult=isAdult;outside=outsideBattle;opted=optedIn;if(!eligible()) invalidateAds(); });}
    private boolean activityUsable(){Activity a=getActivity();return a!=null&&!a.isFinishing()&&!a.isDestroyed();}
    private boolean canPresent(){return resumed&&activityUsable();}
    @Override public void onMainResume(){resumed=true;super.onMainResume();}
    @Override public void onMainPause(){resumed=false;if(!showing&&!consentPresenting)invalidateAds();super.onMainPause();}
    private boolean eligible(){return adult&&outside&&opted;}
    private boolean current(long generation){return generation==adGeneration&&eligible();}
    private void finish(long id,long generation,boolean earned,String message){if(generation!=adGeneration)return;
        loaded=null;pendingTestId=-1;adGeneration++;emitSignal("test_reward_result",id,earned,message);}
    private void invalidateAds(){adGeneration++;loaded=null;long cancelled=pendingTestId;pendingTestId=-1;
        if(cancelled>=0)emitSignal("test_reward_result",cancelled,false,"TEST ad cancelled. No reward granted.");}
    @UsedByGodot public void stop_ads(){ui.execute(this::invalidateAds);}
    @UsedByGodot public void show_rewarded(long id,String placement){emitSignal("reward_result",id,"");}
    @UsedByGodot public boolean is_reward_verified(long id,String transaction){return false;}
    @UsedByGodot public void start_test_rewarded(long id){ui.execute(()->{
        if(initializing && MobileAds.getInitializationStatus()!=null){initializing=false;initialized=true;}
        if(!eligible()||showing||consentPresenting||initializing||!canPresent()){emitSignal("test_reward_result",id,false,"TEST ad unavailable. Guest play is unaffected.");return;}
        final long generation=++adGeneration;pendingTestId=id;
        ConsentInformation consent=UserMessagingPlatform.getConsentInformation(getActivity());
        emitSignal("test_ad_status","Checking Google privacy choices…");
        ConsentRequestParameters parameters=new ConsentRequestParameters.Builder().setTagForUnderAgeOfConsent(false).build();
        consent.requestConsentInfoUpdate(getActivity(),parameters,()->{
            if(!current(generation))return;
            if(!canPresent()){finish(id,generation,false,"Return to the game and retry the TEST ad.");return;}
            if(consent.getConsentStatus()!=ConsentInformation.ConsentStatus.REQUIRED){
                if(consent.canRequestAds())prepareAd(id,generation,consent);
                else finish(id,generation,false,"Privacy consent unavailable. No ad requested.");
                return;
            }
            UserMessagingPlatform.loadConsentForm(getActivity(),form->{
                if(!current(generation))return;
                if(!canPresent()){finish(id,generation,false,"Return to the game and retry the TEST ad.");return;}
                consentPresenting=true;
                form.show(getActivity(),error->{
                    consentPresenting=false;
                    if(!current(generation))return;
                    if(error!=null||!consent.canRequestAds()){finish(id,generation,false,"Privacy consent unavailable. No ad requested.");return;}
                    prepareAd(id,generation,consent);
                });
            },error->finish(id,generation,false,"Privacy form unavailable (code "+error.getErrorCode()+"). No ad requested."));
        },error->finish(id,generation,false,"Privacy check failed (code "+error.getErrorCode()+"). No ad requested."));
    });}
    private void prepareAd(long id,long generation,ConsentInformation consent){
        if(!current(generation)||!consent.canRequestAds())return;
        if(!canPresent()){finish(id,generation,false,"Privacy choices saved. Return to the game and retry the TEST ad.");return;}
        MobileAds.setRequestConfiguration(new RequestConfiguration.Builder()
            .setMaxAdContentRating(RequestConfiguration.MAX_AD_CONTENT_RATING_G).build());
        if(initialized){loadAd(id,generation,consent);return;}
        initializing=true;
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(()->{
            if(!initializing)return;
            if(MobileAds.getInitializationStatus()!=null){
                initializing=false;initialized=true;
                if(current(generation)&&consent.canRequestAds())loadAd(id,generation,consent);
            } else {
                finish(id,generation,false,"Google ad initialization timed out. Restart the app to retry safely.");
            }
        },35000);
        MobileAds.initialize(getActivity(),status->ui.execute(()->{boolean alreadyReady=initialized;initializing=false;initialized=true;
            if(!alreadyReady&&current(generation)&&consent.canRequestAds())loadAd(id,generation,consent);
        }));
    }
    private void loadAd(long id,long generation,ConsentInformation consent){
        if(!current(generation)||!canPresent())return;
        emitSignal("test_ad_status","Loading official Google TEST rewarded ad…");
        RewardedAd.load(getActivity(),TEST_UNIT,new AdRequest.Builder().build(),new RewardedAdLoadCallback(){
            @Override public void onAdFailedToLoad(LoadAdError error){finish(id,generation,false,"TEST ad could not load (code "+error.getCode()+"). Try later.");}
            @Override public void onAdLoaded(RewardedAd ad){
                if(!current(generation)||!consent.canRequestAds())return;
                if(!canPresent()){finish(id,generation,false,"Return to the game and retry the TEST ad.");return;}
                loaded=ad; final boolean[] earned={false};
                ad.setFullScreenContentCallback(new FullScreenContentCallback(){
                    @Override public void onAdDismissedFullScreenContent(){showing=false;
                        finish(id,generation,earned[0],earned[0]?"DEMO reward earned from a Google TEST ad. No cash or real-world value.":"TEST ad closed without a reward.");}
                    @Override public void onAdFailedToShowFullScreenContent(AdError error){showing=false;finish(id,generation,false,"TEST ad could not be displayed (code "+error.getCode()+").");}
                });
                showing=true; loaded=null;
                ad.show(getActivity(),reward->{if(current(generation))earned[0]=true;});
            }
        });
    }
    @UsedByGodot public void show_privacy_options(){ui.execute(()->{
        if(showing||consentPresenting||!canPresent())return;invalidateAds();
        ConsentInformation consent=UserMessagingPlatform.getConsentInformation(getActivity());
        if(consent.getPrivacyOptionsRequirementStatus()!=ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED){
            emitSignal("test_ad_status","No Google privacy options form is currently required.");return;}
        consentPresenting=true;
        UserMessagingPlatform.showPrivacyOptionsForm(getActivity(),error->{consentPresenting=false;emitSignal("test_ad_status",error==null?"Privacy choices updated.":"Privacy choices could not be opened.");});
    });}
    @UsedByGodot public void start_login(long id){ui.execute(()->{
        cancelLogin(); final long generation=loginGeneration;
        if(!canPresent()||!publicClientId.endsWith(".apps.googleusercontent.com")){emitSignal("login_result",id,false);return;}
        byte[] random=new byte[32];new SecureRandom().nextBytes(random);
        String nonce=android.util.Base64.encodeToString(random,android.util.Base64.NO_WRAP|android.util.Base64.URL_SAFE);
        GetSignInWithGoogleOption option=new GetSignInWithGoogleOption.Builder(publicClientId).setNonce(nonce).build();
        GetCredentialRequest request=new GetCredentialRequest.Builder().addCredentialOption(option).build();
        loginCancel=new CancellationSignal();
        CredentialManager.create(getActivity()).getCredentialAsync(getActivity(),request,loginCancel,ui,
            new CredentialManagerCallback<GetCredentialResponse,GetCredentialException>(){
                @Override public void onResult(GetCredentialResponse response){
                    if(generation!=loginGeneration)return; loginCancel=null;
                    Credential credential=response.getCredential();boolean success=false;
                    if(credential instanceof CustomCredential&&credential.getType().equals(GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL)){
                        try {GoogleIdTokenCredential google=GoogleIdTokenCredential.createFrom(credential.getData());
                            success=!google.getIdToken().isEmpty();
                            // Token is never emitted, logged, or persisted. No backend authorization is asserted.
                        } catch(Exception ignored){success=false;}
                    }
                    emitSignal("login_result",id,success);
                }
                @Override public void onError(GetCredentialException error){if(generation==loginGeneration){loginCancel=null;emitSignal("login_result",id,false);}}
            });
    });}
    private void cancelLogin(){loginGeneration++;if(loginCancel!=null){loginCancel.cancel();loginCancel=null;}}
    @UsedByGodot public void cancel_login(long id){ui.execute(this::cancelLogin);}
    @UsedByGodot public void logout(){ui.execute(()->{cancelLogin();invalidateAds();
        if(!publicClientId.endsWith(".apps.googleusercontent.com")||getActivity()==null)return;
        CredentialManager.create(getActivity()).clearCredentialStateAsync(new ClearCredentialStateRequest(),null,ui,
            new CredentialManagerCallback<Void,ClearCredentialException>(){
                @Override public void onResult(Void ignored){}
                @Override public void onError(ClearCredentialException ignored){}
            });
    });}
    @Override public void onMainDestroy(){pendingTestId=-1;cancelLogin();invalidateAds();super.onMainDestroy();}
}
