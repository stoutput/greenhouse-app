import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greenhouse/ambient_lighting.dart';
import 'package:greenhouse/greenhouse_theme.dart';
void main() {
 testWidgets('preview', (tester) async {
 tester.view.physicalSize=const Size(392,820);tester.view.devicePixelRatio=1;
 final key=GlobalKey();
 await tester.pumpWidget(MaterialApp(theme:greenhouseTheme(Brightness.dark),home:RepaintBoundary(key:key,child:Stack(children:[Scaffold(appBar:AppBar(title:const Brand()),body:const Padding(padding:EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('Your financial picture',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),SizedBox(height:24),Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('NET WORTH'),SizedBox(height:12),Text(r'$12,345.67',style:TextStyle(fontSize:36)),SizedBox(height:20),Text('Across your connected accounts')])),SizedBox(height:20),Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('SPENDING THIS MONTH'),SizedBox(height:12),Text(r'$1,240.80',style:TextStyle(fontSize:30)),SizedBox(height:20),LinearProgressIndicator(value:.48)]))]))),Positioned.fill(child:AmbientLighting(now:DateTime(2026,11,10,9)))]))));
 await tester.pumpAndSettle();
 final image=await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
 final png=(await image.toByteData(format:ui.ImageByteFormat.png))!;
 await tester.runAsync(()=>File('/Users/ben/dev/greenhouse-app/.tmp/ambient-preview.png').writeAsBytes(png.buffer.asUint8List()));
 await tester.pumpWidget(const SizedBox());
 });
}
