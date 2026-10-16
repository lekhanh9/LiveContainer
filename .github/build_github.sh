#!/bin/bash
set -e

# copy lc
curl -fL https://github.com/LiveContainer/dylibify/releases/download/1.0/dylibify -o dylibify
chmod +x dylibify
brew install ldid

# move lc to working folder
mv "$archive_path.xcarchive/Products/Applications" Payload

# temporarily move sidestore support framework to tmp before zip
mkdir -p tmp
mv Payload/LiveContainer.app/Frameworks/SideStoreSupport.framework ./tmp

# create pure LiveContainer.ipa
zip -r "$scheme.ipa" "Payload" -x "._*" -x ".DS_Store" -x "__MACOSX"

# restore SideStoreSupport.framework
mv ./tmp/SideStoreSupport.framework Payload/LiveContainer.app/Frameworks
rm -rf tmp

# put sidestore related keys into Info.plist and settings bundle
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups array' ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups: string group.com.SideStore.SideStore' ./Payload/LiveContainer.app/Info.plist

/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1 dict" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLName string com.kdt.livecontainer.sidestoreurlscheme" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes array" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2 dict" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLName string com.kdt.livecontainer.sidestorebackupurlscheme" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLSchemes array" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.kdt.livecontainer" ./Payload/LiveContainer.app/Info.plist

/usr/libexec/PlistBuddy -c "Add :INIntentsSupported array" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :INIntentsSupported:0 string RefreshAllIntent" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :INIntentsSupported:1 string ViewAppIntent" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes array" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes:0 string RefreshAllIntent" ./Payload/LiveContainer.app/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSUserActivityTypes:1 string ViewAppIntent" ./Payload/LiveContainer.app/Info.plist

/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Type string PSToggleSwitchSpecifier" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Title string Open SideStore" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:Key string LCOpenSideStore" ./Payload/LiveContainer.app/Settings.bundle/Root.plist
/usr/libexec/PlistBuddy -c "Add :PreferenceSpecifiers:3:DefaultValue bool false" ./Payload/LiveContainer.app/Settings.bundle/Root.plist

# Save base Payload that has SideStore support plist entries configured
cp -R Payload Payload_base

bundle_sidestore() {
    local ss_url="$1"
    local output_ipa="$2"

    echo "=========================================================="
    echo "Bundling SideStore from: $ss_url"
    echo "Output IPA: $output_ipa"
    echo "=========================================================="

    rm -rf Payload tmp
    cp -R Payload_base Payload
    mkdir -p tmp

    cd tmp
    curl -fL -o SideStore.ipa "$ss_url"
    unzip -q SideStore.ipa
    cd ..

    # Move SideStore to Frameworks
    rm -rf ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework
    mv ./tmp/Payload/SideStore.app ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework

    # Convert SideStore binary to dylib and sign
    ./dylibify ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib
    rm ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
    mv ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore.dylib ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
    ldid -S"" ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/SideStore
    cp ./.github/sidelc/LCAppInfo.plist ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/

    # Copy intents
    cp ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Intents.intentdefinition ./Payload/LiveContainer.app/
    cp ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/ViewApp.intentdefinition ./Payload/LiveContainer.app/
    rm -rf ./Payload/LiveContainer.app/Metadata.appintents
    cp -r ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/Metadata.appintents ./Payload/LiveContainer.app/Metadata.appintents
    sed -i '' 's/9SideStore20RefreshAllAppsIntentV/16SideStoreSupport20RefreshAllAppsIntentV/g' ./Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata
    sed -i '' 's/9SideStore26RefreshAllAppsWidgetIntentV/16SideStoreSupport26RefreshAllAppsWidgetIntentV/g' ./Payload/LiveContainer.app/Metadata.appintents/extract.actionsdata

    # AltWidgetExtension
    rm -rf ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex
    mkdir -p ./Payload/LiveContainer.app/PlugIns
    mv ./Payload/LiveContainer.app/Frameworks/SideStoreApp.framework/PlugIns/AltWidgetExtension.appex ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kdt.livecontainer.LiveWidget" ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable LiveWidgetExtension" ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/Info.plist
    mv ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/AltWidgetExtension ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

    # Sign Widget
    rm -rf .zsign_cache
    find Payload -type d -name "_CodeSignature" -exec rm -rf {} + 2>/dev/null || true
    ldid -S.github/sidelc/LiveWidgetExtension_adhoc.xml ./Payload/LiveContainer.app/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension

    # Package IPA
    zip -r "$output_ipa" "Payload" -x "._*" -x ".DS_Store" -x "__MACOSX"
    echo "Finished packaging $output_ipa"
}

# 1) LiveContainer + SideStore (iOS 17.4+ Remote Pairing + Windows Anisette fix + GrandSlam fix)
bundle_sidestore "https://github.com/lekhanh9/SideStore/releases/download/nightly-fork-17.4+/SideStore.ipa" "$scheme+SideStore.ipa"

# 2) LiveContainer + SideStore-iOS16 (iOS 16 Heartbeat Minimuxer fix + Windows Anisette fix + GrandSlam fix)
bundle_sidestore "https://github.com/lekhanh9/SideStore/releases/download/nightly-fork-16/SideStore.ipa" "$scheme+SideStore-iOS16.ipa"

# Cleanup
rm -rf Payload_base tmp