import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA4J_Ny7DDIjZl_WG81bl_yoNAXoJRP_SA',
    appId: '1:774926504950:web:placeholder',
    messagingSenderId: '774926504950',
    projectId: 'whereinkitchen',
    authDomain: 'whereinkitchen.firebaseapp.com',
    storageBucket: 'whereinkitchen.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA4J_Ny7DDIjZl_WG81bl_yoNAXoJRP_SA',
    appId: '1:774926504950:android:63c3b36eeb828f25faedd7',
    messagingSenderId: '774926504950',
    projectId: 'whereinkitchen',
    storageBucket: 'whereinkitchen.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA4J_Ny7DDIjZl_WG81bl_yoNAXoJRP_SA',
    appId: '1:774926504950:ios:placeholder',
    messagingSenderId: '774926504950',
    projectId: 'whereinkitchen',
    storageBucket: 'whereinkitchen.firebasestorage.app',
    iosBundleId: 'com.whereinkitchen.whereinKitchen',
  );
}
