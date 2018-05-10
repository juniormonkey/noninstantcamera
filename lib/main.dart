import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as Im;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

final googleSignIn = new GoogleSignIn(
  scopes: [
    'email',
    'profile',
  ],
);
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;
final reference = FirebaseDatabase.instance.reference().child('photo-bytes');
final Query randomPhoto = reference.orderByPriority().limitToFirst(1);
String randomPhotoKey;

var rng = new Random();
FirebaseUser currentFirebaseUser;

void main() {
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  runApp(new NonInstantCameraApp());
}

Future<Null> _ensureLoggedIn() async {
  if (await auth.currentUser() == null) {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null) user = await googleSignIn.signInSilently();
    if (user == null) {
      await googleSignIn.signIn();
      analytics.logLogin();
    }
    GoogleSignInAuthentication credentials =
        await googleSignIn.currentUser.authentication;
    await auth.signInWithGoogle(
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
    );
  }

  currentFirebaseUser = await auth.currentUser();
}

class NonInstantCameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Non-Instant Camera',
      theme: new ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: new HomePage(title: 'Non-Instant Camera'),
    );
  }
}

class HomePage extends StatefulWidget {
  HomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _HomePageState createState() => new _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String BYTES_FIELD = 'bytes';
  static const int MAX_PRIORITY = 10000;

  DatabaseError _error;
  bool _waiting = false;
  File _cachedImage;
  File _imageFile;
  String _randomPhotoKey;

  @override
  void initState() {
    super.initState();

    randomPhoto.onValue.listen((Event event) async {
      print("### randomPhoto.onValue: ${event.snapshot}");
      if (event.snapshot.value != null) {
        event.snapshot.value.forEach((key, value) async {
          _randomPhotoKey = key;
          Directory photosDir = await getTemporaryDirectory();
          String timestamp =
          new DateFormat('yyyyMMddHms').format(new DateTime.now());
          _cachedImage =
              await new File('${photosDir.path}/photo_${timestamp}.png').create();
          _cachedImage.writeAsBytesSync(BASE64.decode(value[BYTES_FIELD]));
          print("### randomPhoto.onValue: written to ${_cachedImage.path}");
        });
      }
    }, onError: (Object o) {
      final DatabaseError error = o;
      setState(() {
        _error = error;
      });
    });
  }

  _store(File image) async {
    await _ensureLoggedIn();

    int priority = rng.nextInt(MAX_PRIORITY);
    print ("#### _store(): new priority ${priority}");
    reference.push().set({
      BYTES_FIELD: _compressAndEncode(image),
      'senderId': currentFirebaseUser.uid,
      'senderEmail': currentFirebaseUser.email,
    }, priority: priority);
  }

  String _compressAndEncode(File imageFile) {
    Im.Image image = Im.decodeImage(imageFile.readAsBytesSync());
    Im.Image smallerImage = Im.copyResize(image, 1500);

    return BASE64.encode(Im.encodePng(smallerImage));
  }

  _display() async {
    print("### _display: ${_randomPhotoKey}, ${_cachedImage}");
    if (_cachedImage!= null && _randomPhotoKey != null) {
      setState(() {
        _waiting = false;
        _imageFile = _cachedImage;
      });
      // Shuffle instead of remove. TODO(martin): reconsider this perhaps?
      // _randomPhoto.reference().remove();
      int priority = rng.nextInt(MAX_PRIORITY);
      print ("#### _display(): new priority ${priority}");
      randomPhoto
          .reference()
          .child(_randomPhotoKey)
          .setPriority(priority);
    }
  }

  takePhoto() async {
    setState(() {
      _waiting = true;
    });
    await _ensureLoggedIn();
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    await _store(_photo);
    await _display();
    analytics.logEvent(name: 'new_photo');
  }

  pickExistingImage() async {
    setState(() {
      _waiting = true;
    });
    await _ensureLoggedIn();
    var _existingImage =
        await ImagePicker.pickImage(source: ImageSource.gallery);
    await _store(_existingImage);
    await _display();
    analytics.logEvent(name: 'existing_image');
  }

  ensureLoggedIn() async {
    await _ensureLoggedIn();
    setState(() {});
  }

  shareImage() {
    if (_imageFile != null) {
      try {
        print('### shareImage: "${_imageFile.path}"');
        final channel = const MethodChannel(
            'channel:au.id.martinstrauss.noninstantcamera.share/share');
        channel.invokeMethod('shareFile', basename(_imageFile.path));
      } catch (e) {
        print('Share error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: const Text('Non-Instant Camera'),
      ),
      body: new Center(child: _imageViewer()),
      floatingActionButton: new FloatingActionButton(
        onPressed: takePhoto,
        tooltip: 'Take new photo',
        child: new Icon(Icons.add_a_photo),
      ),
      persistentFooterButtons: [
        new FlatButton(
          onPressed: ensureLoggedIn,
          child: new Icon(currentFirebaseUser == null
              ? Icons.lock_outline
              : Icons.lock_open),
        ),
        new FlatButton(
          onPressed: pickExistingImage,
          child: new Icon(Icons.add),
        ),
        new FlatButton(
          onPressed: _imageFile == null ? null : shareImage,
          child: new Icon(Icons.share),
        ),
      ],
    );
  }

  Widget _imageViewer() {
    if (_waiting) {
      return const CircularProgressIndicator();
    }
    if (_imageFile == null) {
      if (_error != null) {
        return new Text('Error: ${_error.code} ${_error.message}');
      } else {
        return new Text('Select an image');
      }
    }
    return new Image.file(_imageFile);
  }
}
