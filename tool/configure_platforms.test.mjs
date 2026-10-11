import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, cp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {configurePlatforms} from './configure_platforms.mjs';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
test('native configuration preserves existing URL schemes and is repeatable', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'dayweave-platform-test-'));
  t.after(() => rm(root, {recursive: true}));
  await cp(join(repository, 'native'), join(root, 'native'), {recursive: true});
  await mkdir(join(root, 'android/app'), {recursive: true});
  await mkdir(join(root, 'ios/Runner'), {recursive: true});
  await writeFile(join(root, 'android/app/build.gradle.kts'), 'android { compileOptions { } }\n');
  await writeFile(join(root, 'ios/Runner/Info.plist'),
    '<plist><dict><key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key>' +
    '<array><string>existing</string></array></dict></array></dict></plist>');
  const environment = {GOOGLE_REVERSED_CLIENT_ID:'com.googleusercontent.apps.example'};
  await configurePlatforms(root, environment);
  const gradle = await readFile(join(root, 'android/app/build.gradle.kts'), 'utf8');
  const plist = await readFile(join(root, 'ios/Runner/Info.plist'), 'utf8');
  await configurePlatforms(root, environment);
  assert.equal(await readFile(join(root, 'android/app/build.gradle.kts'), 'utf8'), gradle);
  assert.equal(await readFile(join(root, 'ios/Runner/Info.plist'), 'utf8'), plist);
  assert.match(plist, /<string>existing<\/string>/);
  assert.match(plist, /<string>dayweave<\/string>/);
  assert.match(plist, /NSCalendarsFullAccessUsageDescription/);
  assert.match(plist, /com.googleusercontent.apps.example/);
  const manifest = await readFile(join(root, 'android/app/src/main/AndroidManifest.xml'), 'utf8');
  assert.match(manifest, /android:allowBackup="false"/);
  assert.match(manifest, /android:scheme="dayweave"/);
  assert.match(manifest, /POST_NOTIFICATIONS/);
  assert.match(manifest, /ScheduledNotificationBootReceiver/);
  assert.match(await readFile(join(root, 'android/app/src/main/res/xml/quick_add_widget_info.xml'), 'utf8'), /home_screen\|keyguard/);
  assert.match(await readFile(join(root, 'ios/QuickAddWidget/QuickAddWidget.swift'), 'utf8'), /dayweave:\/\/add/);
});
test('missing Flutter scaffold fails without writing platform files', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'dayweave-missing-scaffold-'));
  t.after(() => rm(root, {recursive:true}));
  await assert.rejects(configurePlatforms(root, {}), {code:'ENOENT'});
  await assert.rejects(readFile(join(root, 'android/app/src/main/AndroidManifest.xml')), {code:'ENOENT'});
});
