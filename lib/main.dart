import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final googleSignIn = new GoogleSignIn();
final auth = FirebaseAuth.instance;

void main() => runApp(new NonInstantCameraApp());

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
  File imageFile;

  ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null)
      user = await googleSignIn.signInSilently();
    if (user == null) {
      await googleSignIn.signIn();
    }

    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
      await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }
  }

  takePhoto() async {
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    setState(() {
      imageFile = _photo;
    });
  }

  pickExistingImage() async {
    var _existingImage = await ImagePicker.pickImage(source: ImageSource.gallery);
    setState(() {
      imageFile = _existingImage;
    });
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
          child: imageFile == null
              ? new Text('Select an image.')
              : new Image.file(imageFile)
      ),
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
