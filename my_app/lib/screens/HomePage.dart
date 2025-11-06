import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("App Bar"),
        centerTitle: true,
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: GestureDetector(
          onTap: () => {
            Navigator.pushNamed(
                    context,
                    '/detectionmethod'
                  )
          },
          child: Container(
            color: Colors.red,
            height: 100,
            width: 100,
            child: Center(child: Text("Click")),
          ),
        )

      ),
    );
  }
}