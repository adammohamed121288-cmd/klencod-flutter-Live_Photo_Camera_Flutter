# Live Photo Camera — Flutter

نسخة أولية عملية لكاميرا بأسلوب iPhone على Android وiOS.

## التشغيل
1. ثبّت Flutter وAndroid Studio أو افتح المشروع في VS Code.
2. نفّذ داخل مجلد المشروع:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons
   flutter run
   ```
3. وافق على إذن الكاميرا عند أول تشغيل.

## ملاحظة مهمة عن Live Photo
هذه النسخة تنشئ «صورة لايف» بأسلوب مشابه: تسجل مقطعًا قصيرًا مدته 3 ثوانٍ، وتنشئ منه صورة غلاف ثابتة، ثم تعرض الاثنين معًا داخل التطبيق. هذا ليس تنسيق Apple Live Photo الأصلي المكوّن من HEIC/MOV مع بيانات الربط الخاصة بآبل. كما أن تأثير Bounce هنا واجهة أولية وليس عكسًا فعليًا للفيديو.

## الأيقونة
الأيقونة موجودة في `assets/app_icon.png`، ويتم توليد أيقونات Android وiOS بأمر `dart run flutter_launcher_icons`.

## أذونات Android
أضف داخل `android/app/src/main/AndroidManifest.xml` قبل وسم application:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```
ولا حاجة إلى تسجيل الصوت لأن التطبيق يسجل الفيديو بدون صوت.

## أذونات iOS
أضف إلى `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>نحتاج إلى الكاميرا لالتقاط صور Live Photo.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>نحتاج إلى حفظ صورك ومقاطعك في مكتبة الصور.</string>
```
