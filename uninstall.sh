#!/bin/bash
# Apfelbindung Uninstaller
echo "Uninstalling Apfelbindung..."

# Kill the app
killall Apfelbindung 2>/dev/null

# Remove the app
rm -rf /Applications/Apfelbindung.app

# Remove app data
rm -rf ~/Library/Application\ Support/Apfelbindung
rm -rf ~/Library/Caches/Apfelbindung

# Remove preferences
defaults delete com.apfelbindung.app 2>/dev/null

# Unregister from LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/Apfelbindung.app 2>/dev/null

# Remove legacy KonnectMac install (pre-rename fork / upstream)
killall KonnectMac 2>/dev/null
rm -rf /Applications/KonnectMac.app
rm -rf ~/Library/Application\ Support/KonnectMac
rm -rf ~/Library/Caches/KonnectMac
rm -f ~/Library/LaunchAgents/com.konnectmac.app.plist
defaults delete com.konnectmac.app 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/KonnectMac.app 2>/dev/null

# Reset notification registration
killall usernoted 2>/dev/null

# Logs are in ~/Library/Application Support/Apfelbindung/ (removed above)

echo "Apfelbindung has been uninstalled."
echo "Note: Notification and Login Item entries in System Settings may take a restart to disappear."
