"""Configure the local Godot editor without storing machine paths in source."""
import argparse
import os
import pathlib
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--sdk', default=os.getenv('ANDROID_HOME', os.getenv('ANDROID_SDK_ROOT', '')))
p.add_argument('--java', default=os.getenv('JAVA_HOME', ''))
args = p.parse_args()
sdk, java = pathlib.Path(args.sdk).resolve(), pathlib.Path(args.java).resolve()
if not (sdk/'platform-tools/adb').is_file() or not (java/'bin/java').is_file():
    raise SystemExit('Pass --sdk and --java pointing to the Android SDK and JDK 17+.')
config_root = pathlib.Path(os.getenv('XDG_CONFIG_HOME', str(pathlib.Path.home()/'.config')))/'godot'
config_root.mkdir(parents=True, exist_ok=True)
keystore = pathlib.Path.home()/'.android/debug.keystore'
keystore.parent.mkdir(parents=True, exist_ok=True)
if not keystore.exists():
    subprocess.run([str(java/'bin/keytool'), '-genkeypair', '-keystore', str(keystore),
                    '-storepass', 'android', '-alias', 'androiddebugkey', '-keypass', 'android',
                    '-dname', 'CN=Android Debug,O=Android,C=US', '-keyalg', 'RSA',
                    '-keysize', '2048', '-validity', '10000'], check=True)
settings = config_root/'editor_settings-4.6.tres'
lines = settings.read_text().splitlines() if settings.exists() else [
    '[gd_resource type="EditorSettings" format=3]', '', '[resource]']
replacements = {
    'export/android/android_sdk_path': str(sdk),
    'export/android/java_sdk_path': str(java),
    'export/android/debug_keystore': str(keystore),
    'export/android/debug_keystore_user': 'androiddebugkey',
    'export/android/debug_keystore_pass': 'android',
}
lines = [line for line in lines if not any(line.startswith(key+' ') for key in replacements)]
lines.extend(f'{key} = "{value}"' for key, value in replacements.items())
settings.write_text('\n'.join(lines)+'\n')
print('Android SDK, JDK and disposable debug signing configured.')
