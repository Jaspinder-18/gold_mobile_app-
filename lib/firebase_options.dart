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
    apiKey: 'AIzaSyD-placeholder-key-for-web-fcm',
    appId: '1:114409035526:web:b2089e9f93539281a70014',
    messagingSenderId: '114409035526',
    projectId: 'telichat-4c031',
    authDomain: 'telichat-4c031.firebaseapp.com',
    storageBucket: 'telichat-4c031.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD-placeholder-key-for-android-fcm',
    appId: '1:114409035526:android:b2089e9f93539281a70014',
    messagingSenderId: '114409035526',
    projectId: 'telichat-4c031',
    storageBucket: 'telichat-4c031.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD-placeholder-key-for-ios-fcm',
    appId: '1:114409035526:ios:b2089e9f93539281a70014',
    messagingSenderId: '114409035526',
    projectId: 'telichat-4c031',
    storageBucket: 'telichat-4c031.appspot.com',
    iosBundleId: 'com.gold.alert.goldMobileApp',
  );
}
