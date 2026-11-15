import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
// استخدام مسار نسبي مباشر بيلغي أي مشاكل في اسم المشروع
import '../lib/main.dart';

void main() {
  testWidgets('التطبيق يعمل بشكل صحيح', (tester) async {
    // بناء التطبيق
    await tester.pumpWidget(const StudyPaceApp());

    // التحقق من ظهور الواجهة الرئيسية
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}