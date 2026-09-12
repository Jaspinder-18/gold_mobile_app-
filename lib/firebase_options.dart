import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Generated for project `telichat-4c031`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDBXUjucFx4R-Ydvx2S_buZh3aNiq-EuwQ',
    appId: '1:395068005465:web:b2089e9f93539281a70014',
    messagingSenderId: '395068005465',
    projectId: 'alert-96e3b',
    authDomain: 'alert-96e3b.firebaseapp.com',
    storageBucket: 'alert-96e3b.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDBXUjucFx4R-Ydvx2S_buZh3aNiq-EuwQ',
    appId: '1:395068005465:android:f2b83a12b595452d582548',
    messagingSenderId: '395068005465',
    projectId: 'alert-96e3b',
    storageBucket: 'alert-96e3b.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDBXUjucFx4R-Ydvx2S_buZh3aNiq-EuwQ',
    appId: '1:395068005465:ios:b2089e9f93539281a70014',
    messagingSenderId: '395068005465',
    projectId: 'alert-96e3b',
    storageBucket: 'alert-96e3b.firebasestorage.app',
    iosBundleId: 'com.gold.alert.goldMobileApp',
  );
}
