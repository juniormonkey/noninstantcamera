import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

final googleSignIn = new GoogleSignIn(
  scopes: [
    'email',
    'profile',
  ],
);
final analytics = new FirebaseAnalytics();
final auth = FirebaseAuth.instance;
final reference = FirebaseDatabase.instance.reference().child('photo');

var rng = new Random();
FirebaseUser currentFirebaseUser = null;

void main() {
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  reference.keepSynced(true);
  runApp(new NonInstantCameraApp());
}

Future<Null> _ensureLoggedIn() async {
  GoogleSignInAccount user = googleSignIn.currentUser;
  if (user == null) user = await googleSignIn.signInSilently();
  if (user == null) {
    await googleSignIn.signIn();
    analytics.logLogin();
  }
  if (await auth.currentUser() == null) {
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
  String imageUrl;

  _store(File image) async {
    setState(() {
      waiting = true;
    });
    await _ensureLoggedIn();
    int random = rng.nextInt(100000);
    StorageReference ref =
    FirebaseStorage.instance.ref().child("image_$random.jpg");
    StorageUploadTask uploadTask = ref.put(image); 
    Uri downloadUrl = (await uploadTask.future).downloadUrl;

    reference.push().set({
      'file': downloadUrl.toString(),
      'senderId': currentFirebaseUser.uid,
      'senderEmail': currentFirebaseUser.email,
    }, priority: rng.nextInt(10000));

    var _randomPhoto = reference.orderByPriority().limitToFirst(1);
    var _dataSnapshot = await _randomPhoto.once();
    _dataSnapshot.value.forEach((key, value) {
      setState(() {
        waiting = false;
        imageUrl = value['file'];
        //  _randomPhoto.reference().remove();
        _randomPhoto.reference().child(key).setPriority(rng.nextInt(10000));
      });
    });
  }

  takePhoto() async {
    await _ensureLoggedIn();
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    await _store(_photo);
    analytics.logEvent(name: 'new_photo');
  }

  pickExistingImage() async {
    await _ensureLoggedIn();
    var _existingImage =
    await ImagePicker.pickImage(source: ImageSource.gallery);
    await _store(_existingImage);
    analytics.logEvent(name: 'existing_image');
  }

  ensureLoggedIn() async {
    await _ensureLoggedIn();
  }

  shareImage() {
    if (imageUrl != null) {
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
              : (imageUrl == null
              ? new Text('Select an image.')
              : new Image.network(imageUrl))),
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
