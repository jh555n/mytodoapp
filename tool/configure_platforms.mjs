import { readFile, writeFile, mkdir, copyFile, cp } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export async function configurePlatforms(root, environment = process.env) {
// Fail before copying if the Flutter platform scaffold hasn't been created yet.
await readFile(resolve(root, 'android/app/build.gradle.kts'), 'utf8');
await readFile(resolve(root, 'ios/Runner/Info.plist'), 'utf8');
async function copy(source, destination) {
  await mkdir(dirname(resolve(root, destination)), { recursive: true });
  await copyFile(resolve(root, source), resolve(root, destination));
}
await copy('native/android/AndroidManifest.xml', 'android/app/src/main/AndroidManifest.xml');
await copy('native/android/MainActivity.kt', 'android/app/src/main/kotlin/dev/dayweave/dayweave/MainActivity.kt');
await copy('native/android/QuickAddWidget.kt', 'android/app/src/main/kotlin/dev/dayweave/dayweave/QuickAddWidget.kt');
await cp(resolve(root, 'native/android/res'), resolve(root, 'android/app/src/main/res'), { recursive: true });
await copy('native/ios/AppDelegate.swift', 'ios/Runner/AppDelegate.swift');
await copy('native/ios/QuickAddWidget.swift', 'ios/QuickAddWidget/QuickAddWidget.swift');
await copy('native/ios/WidgetInfo.plist', 'ios/QuickAddWidget/Info.plist');

const gradlePath = resolve(root, 'android/app/build.gradle.kts');
let gradle = await readFile(gradlePath, 'utf8');
if (!gradle.includes('isCoreLibraryDesugaringEnabled')) {
  gradle = gradle.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
}
if (!gradle.includes('desugar_jdk_libs')) {
  gradle += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n';
}
await writeFile(gradlePath, gradle);
const plistPath = resolve(root, 'ios/Runner/Info.plist');
let plist = await readFile(plistPath, 'utf8');
const add = (key, xml) => {
  if (!plist.includes(`<key>${key}</key>`)) {
    plist = plist.replace(/<\/dict>\s*<\/plist>\s*$/, `<key>${key}</key>${xml}\n</dict>\n</plist>\n`);
  }
};
add('NSCalendarsUsageDescription', '<string>선택한 캘린더의 일정을 보고 할 일을 등록합니다.</string>');
add('NSCalendarsFullAccessUsageDescription', '<string>선택한 캘린더의 일정과 색상을 가져오고 앱에서 만든 할 일을 동기화합니다.</string>');
add('FlutterDeepLinkingEnabled', '<false/>');
const reversedClientId = environment.GOOGLE_REVERSED_CLIENT_ID;
if (reversedClientId && !/^[a-zA-Z0-9.-]+$/.test(reversedClientId)) {
  throw new Error('GOOGLE_REVERSED_CLIENT_ID must be a URL scheme, not a credential.');
}
if (!plist.includes('<key>CFBundleURLTypes</key>')) {
  add('CFBundleURLTypes', `<array><dict><key>CFBundleURLSchemes</key><array><string>dayweave</string>${
    reversedClientId ? `<string>${reversedClientId}</string>` : ''}</array></dict></array>`);
} else if (reversedClientId && !plist.includes(`<string>${reversedClientId}</string>`)) {
  plist = plist.replace(/(<key>CFBundleURLSchemes<\/key>\s*<array>)/,
    `$1<string>${reversedClientId}</string>`);
}
if (!plist.includes('<string>dayweave</string>')) {
  plist = plist.replace(/(<key>CFBundleURLSchemes<\/key>\s*<array>)/, '$1<string>dayweave</string>');
}
await writeFile(plistPath, plist);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await configurePlatforms(resolve(dirname(fileURLToPath(import.meta.url)), '..'));
  console.log('Android/iOS native integration configured. No credentials were written.');
}
