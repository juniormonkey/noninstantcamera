import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:connectivity/connectivity.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
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
final reference = FirebaseDatabase.instance.reference().child('photo');

var rng = new Random();
FirebaseUser currentFirebaseUser;

void main() {
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  runApp(new NonInstantCameraApp());
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

  String _placeholderText = "Select an image";
  bool _waiting = false;
  File _imageFile;
  BuildContext _context;

  StreamSubscription<Event> _dbSubscription;
  StreamSubscription<ConnectivityResult> _connectivitySubscription;

  Queue<String> uploadQueue = new Queue();

  @override
  void initState() {
    super.initState();

    _dbSubscription = reference.onValue.listen((Event event) async {
      if (event.snapshot.value != null) {
        event.snapshot.value.forEach((key, value) async {
          await cache(value['file']);
        });
      }
    }, onError: (Object o) {
      final DatabaseError error = o;
      error('DatabaseError: ${error.code} ${error.message}');
    });

    _connectivitySubscription = new Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) async {
      if (result == ConnectivityResult.none) {
        // Don't try to upload if there's no Internet.
        return;
      }
      if (uploadQueue.length == 0) {
        // Don't try to remove anything if the queue is empty.
        return;
      }
      var filename;
      while (filename = uploadQueue.removeFirst() != null) {
        await _upload(filename);
      }
    });
  }

  dispose() {
    _dbSubscription.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<Null> _ensureLoggedIn() async {
    try {
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
    } catch (e) {
      error('_ensureLoggedIn: $e');
    }
  }

  Future<String> _localFileName(String basename) async {
    Directory photosDir = await getTemporaryDirectory();
    return '${photosDir.path}/$basename';
  }

  Future<File> cache(String url) async {
    var file = new File(await _localFileName(Uri.parse(url).pathSegments.last));
    if (await file.exists()) {
      return file;
    }

    final connectivityResult = await (new Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      // Don't try to fetch from cache if there's no Internet.
      return null;
    }

    await _ensureLoggedIn();
    final response = await http.get(url);
    if (response.statusCode != 200) {
      error('HTTP error: ${response.statusCode}');
      print(response.body);
      return null;
    }

    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  _store(File image) async {
    String timestamp = new DateFormat('yyyyMMddHms').format(new DateTime.now());
    String filename = await _localFileName('image_$timestamp.jpg');
    await image.copy(filename);

    final connectivityResult = await (new Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      // Don't try to upload if there's no Internet.
      uploadQueue.add(filename);
    } else {
      _upload(filename);
    }
  }

  _upload(String filename) async {
    await _ensureLoggedIn();

    File imageFile = new File(filename);
    StorageReference ref =
        FirebaseStorage.instance.ref().child(basename(imageFile.path));
    StorageUploadTask uploadTask = ref.putFile(imageFile);
    try {
      Uri downloadUrl = (await uploadTask.future).downloadUrl;

      int priority = rng.nextInt(MAX_PRIORITY);
      reference.push().set({
        'file': downloadUrl.toString(),
        'senderId': currentFirebaseUser.uid,
        'senderEmail': currentFirebaseUser.email,
      }, priority: priority);
    } catch (e) {
      error('_upload: $e');
      uploadQueue.add(filename);
    }
  }

  static const int MAX_NUM_RETRIES = 10;

  _display() async {
    var randomPhoto = reference.orderByPriority().limitToFirst(MAX_NUM_RETRIES);
    var cachedFile;
    var cachedKey;

    var dataSnapshot = await randomPhoto.once();
    for (var key in dataSnapshot.value.keys) {
      cachedFile = await cache(dataSnapshot.value[key]['file']);
      if (cachedFile != null) {
        cachedKey = key;
        break;
      }
    }
    if (cachedFile != null) {
      setState(() {
        _waiting = false;
        _imageFile = cachedFile;
      });
      // Shuffle instead of remove. TODO(martin): reconsider this perhaps?
      // _randomPhoto.reference().remove();
      int priority = rng.nextInt(MAX_PRIORITY);
      randomPhoto.reference().child(cachedKey).setPriority(priority);
    }
  }

  takePhoto() async {
    setState(() {
      _waiting = true;
    });
    var _photo = await ImagePicker.pickImage(source: ImageSource.camera);
    await _store(_photo);
    await _display();
    analytics.logEvent(name: 'new_photo');
  }

  pickExistingImage() async {
    setState(() {
      _waiting = true;
    });
    var _existingImage =
        await ImagePicker.pickImage(source: ImageSource.gallery);
    await _store(_existingImage);
    await _display();
    analytics.logEvent(name: 'existing_image');
  }

  ensureLoggedIn() async {
    await _ensureLoggedIn();
    notify("Signed in successfully.");
    setState(() {});
  }

  shareImage() {
    if (_imageFile != null) {
      try {
        final channel = const MethodChannel(
            'channel:au.id.martinstrauss.noninstantcamera.share/share');
        channel.invokeMethod('shareFile', basename(_imageFile.path));
      } catch (e) {
        error('shareImage: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: new Builder(builder: (BuildContext context) {
        _context = context;
        return new Center(child: _imageViewer());
      }),
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
      return new Text(_placeholderText);
    }
    return new Image.file(_imageFile);
  }

  void notify(String message) {
    print(message);
    if (_context != null) {
      Scaffold
          .of(_context)
          .showSnackBar(new SnackBar(content: new Text(message)));
    }
  }

  void error(String message) {
    message = 'ERROR: $message';
    setState(() {
      _placeholderText = message;
    });
    notify(message);
  }
}
