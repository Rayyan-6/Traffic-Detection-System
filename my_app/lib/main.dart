import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:my_app/firebase_options.dart';
import 'package:my_app/screens/DetectionMethodPage.dart';
import 'package:my_app/screens/HomePage.dart';
import 'package:my_app/screens/LiveCameraPage.dart';
import 'package:my_app/screens/LoginPage.dart';
import 'package:my_app/screens/SignupPage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_app/screens/UploadVideoPage.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      routes: <String, WidgetBuilder>{
        '/login': (BuildContext context) =>const LoginPage(),
        '/signup': (BuildContext context) =>const SignupPage(),
        '/detectionmethod': (BuildContext context) =>const DetectionMethodPage(),
        '/livecamera': (BuildContext context) =>const LiveCameraPage(),
        '/uploadvideopage': (BuildContext context) =>const UploadVideoPage(),
      },
      theme: ThemeData(
        
        // colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // home: FirebaseAuth.instance.currentUser !=null ? const HomePage() : const SignupPage(),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(), 
        builder: (context, snapshot){

          if(snapshot.connectionState==ConnectionState.waiting){
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.data!= null){
            return const HomePage();
          }
          return const SignupPage();
        }
        )
    );
  }
}


