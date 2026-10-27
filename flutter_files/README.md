# تطبيق وصلت؟ طمّني (Flutter)

التطبيق ده بيتوصل بالباك إند (`tammenny/server.js`) اللي لازم يكون منشور على الإنترنت (Render مثلاً).

## الخطوات
1. ثبّت Flutter: https://docs.flutter.dev/get-started/install ثم شغّل `flutter doctor` وظبّط أي علامة حمرا.
2. اعمل مشروع جديد:
       flutter create tammenny_app
       cd tammenny_app
3. استبدل `lib/main.dart` بالملف اللي في الفولدر ده.
4. ضيف المكتبات:
       flutter pub add http geolocator shared_preferences url_launcher share_plus:^10.1.4
5. افتح `android/app/src/main/AndroidManifest.xml` وانسخ جواه محتوى `android_manifest_additions.xml`
   (الـ permissions فوق وسم `<application>`، والـ queries فوقه كمان).
6. افتح `lib/main.dart` وغيّر `baseUrl` للينك السيرفر بتاعك (https://xxxx.onrender.com).
7. وصّل موبايل أندرويد (USB debugging) وشغّل:
       flutter run
8. لعمل ملف APK للتسليم:
       flutter build apk --release
   الملف هيبقى في: build/app/outputs/flutter-apk/app-release.apk

## iOS (لو محتاج)
في ios/Runner/Info.plist ضيف NSLocationWhenInUseUsageDescription و
NSLocationAlwaysAndWhenInUseUsageDescription وUIBackgroundModes = location. (محتاج ماك وXcode.)

## ملاحظات
- لتجربة الإيميوليتر مع سيرفر على جهازك: baseUrl = http://10.0.2.2:3000 وضيف android:usesCleartextTraffic="true" في وسم <application>.
- لو حصل خطأ في نسخ المكتبات: flutter pub upgrade
