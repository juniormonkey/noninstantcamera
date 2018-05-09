import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

//import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as Im;
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

var rng = new Random();
FirebaseUser currentFirebaseUser;

void main() {
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  reference.keepSynced(true);
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
  bool waiting = false;
  File imageFile;

  _store(File image) async {
    setState(() {
      waiting = true;
    });
    await _ensureLoggedIn();

    reference.push().set({
      'bytes': _compressAndEncode(image),
      'senderId': currentFirebaseUser.uid,
      'senderEmail': currentFirebaseUser.email,
    }, priority: rng.nextInt(10000));
  }

  String _compressAndEncode(File imageFile) {
    Im.Image image = Im.decodeImage(imageFile.readAsBytesSync());
    Im.Image smallerImage = Im.copyResize(image, 1500);

    return BASE64.encode(Im.encodePng(smallerImage));
  }

  _display() async {
    var _randomPhoto = reference.orderByPriority().limitToFirst(1);
    var _dataSnapshot = await _randomPhoto.once();
    Directory tempDir = await getTemporaryDirectory();
    _dataSnapshot.value.forEach((key, value) {
      var file = File(tempDir.path + '/photo.png')
        ..writeAsBytesSync(BASE64.decode(value['bytes']));
      setState(() {
        waiting = false;
        imageFile = file;
      });
      //  _randomPhoto.reference().remove();
      _randomPhoto.reference().child(key).setPriority(rng.nextInt(10000));
    });
  }

  takePhoto() async {
    await _ensureLoggedIn();
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    await _store(_photo);
    await _display();
    analytics.logEvent(name: 'new_photo');
  }

  pickExistingImage() async {
    await _ensureLoggedIn();
    var _existingImage =
        await ImagePicker.pickImage(source: ImageSource.gallery);
    await _store(_existingImage);
    await _display();
    analytics.logEvent(name: 'existing_image');
  }

  ensureLoggedIn() async {
    await _ensureLoggedIn();
  }

  shareImage() {
    if (imageFile != null) {
      // See https://github.com/flutter/flutter/issues/12264
      // Also "share" only allows sharing of text, not images.
      // Perhaps we need to use android_intent or url_launcher instead?
      // share(imageFile.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: const Text('Non-Instant Camera'),
      ),
      body: new Center(
          child: waiting
              ? const CircularProgressIndicator()
              : (imageFile == null
                  ? new Text('Select an image.')
                  : new Image.file(imageFile))),
      floatingActionButton: new FloatingActionButton(
        onPressed: takePhoto,
        tooltip: 'Take new photo',
        child: new Icon(Icons.add_a_photo),
      ),
      persistentFooterButtons: [
        new FlatButton(
          onPressed: ensureLoggedIn,
          child: new Icon(Icons.lock_open),
        ),
        new FlatButton(
          onPressed: pickExistingImage,
          child: new Icon(Icons.add),
        ),
        new FlatButton(
          onPressed: shareImage,
          child: new Icon(Icons.share),
        ),
      ],
    );
  }
}
