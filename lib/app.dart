import 'package:flutter/material.dart';

import 'data/forum_repository.dart';
import 'ui/viewer_page.dart';

class AaFanclubApp extends StatelessWidget {
  AaFanclubApp({ForumRepository? repository, super.key})
    : repository = repository ?? NetworkForumRepository();

  final ForumRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AA同好会揭示板',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: 'Saitamaar',
        scaffoldBackgroundColor: const Color(0xffefefef),
        canvasColor: const Color(0xffefefef),
        primarySwatch: Colors.blue,
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0x663399ff),
        ),
      ),
      home: ViewerPage(repository: repository),
    );
  }
}
