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
  static const String BYTES_FIELD = 'bytes';

  bool waiting = false;
  File imageFile;

  _store(File image) async {
    await _ensureLoggedIn();

    reference.push().set({
      BYTES_FIELD: _compressAndEncode(image),
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
    Directory photosDir = await getTemporaryDirectory();
    //Directory photosDir = await getApplicationDocumentsDirectory();
    String timestamp = new DateFormat('yyyyMMddHms').format(new DateTime.now());
    var file =
        await new File('${photosDir.path}/photo_${timestamp}.png').create();
    _dataSnapshot.value.forEach((key, value) {
      file.writeAsBytesSync(BASE64.decode(value[BYTES_FIELD]));
      setState(() {
        waiting = false;
        imageFile = file;
      });
      //  _randomPhoto.reference().remove();
      _randomPhoto.reference().child(key).setPriority(rng.nextInt(10000));
    });
  }

  takePhoto() async {
    setState(() {
      waiting = true;
    });
    await _ensureLoggedIn();
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    await _store(_photo);
    await _display();
    analytics.logEvent(name: 'new_photo');
  }

  pickExistingImage() async {
    setState(() {
      waiting = true;
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
    if (imageFile != null) {
      try {
        print('### shareImage: "${imageFile.path}"');
        final channel = const MethodChannel(
            'channel:au.id.martinstrauss.noninstantcamera.share/share');
        channel.invokeMethod('shareFile', basename(imageFile.path));
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
          child: new Icon(currentFirebaseUser == null ? Icons.lock_outline : Icons.lock_open),
        ),
        new FlatButton(
          onPressed: pickExistingImage,
          child: new Icon(Icons.add),
        ),
        new FlatButton(
          onPressed: imageFile == null ? null : shareImage,
          child: new Icon(Icons.share),
        ),
      ],
    );
  }
}
